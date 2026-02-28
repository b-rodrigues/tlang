(* src/packages/stats/vcov.ml *)
open Ast

(** vcov(model) — returns the variance-covariance matrix of the coefficients.
    For imported models without a full matrix, returns a diagonal matrix. *)
(*
--# Variance-Covariance Matrix
--#
--# Returns the variance-covariance matrix of the model coefficients.
--# For native T models, the full matrix is returned. For imported models,
--# a diagonal matrix based on standard errors is returned as a fallback.
--#
--# @name vcov
--# @param model :: Model The model object.
--# @return :: DataFrame A square matrix representation with term names.
--#
--# @details
--# The Variance-Covariance matrix ($\Sigma$) is a fundamental diagnostic tool:
--#
--# * **Diagonal elements**: represent the variance of each coefficient estimate ($Var(\hat{\beta}_j)$).
--#   The square root of these values gives the Standard Errors (SE).
--# * **Off-diagonal elements**: represent the covariance between pairs of coefficient 
--#   estimates ($Cov(\hat{\beta}_j, \hat{\beta}_k)$).
--#
--# For native models, this is calculated directly from the $(X^T X)^{-1} \cdot \hat{\sigma}^2$
--# matrix. For imported models, we provide a diagonal matrix based on the reported 
--# standard errors as a fallback.
--#
--# @example
--#   model = lm(mpg ~ wt, data: mtcars)
--#   v = vcov(model)
--# @family stats
--# @export
*)
let register env =
  Env.add "vcov"
    (make_builtin ~name:"vcov" 1 (fun args _env ->
      match args with
      | [VDict pairs] ->
        let model_data = match List.assoc_opt "_model_data" pairs with
          | Some (VDict d) -> d
          | _ -> pairs
        in
        let tidy = match List.assoc_opt "_tidy_df" pairs with
          | Some (VDataFrame df) -> Some df
          | _ -> None
        in
        (match tidy with
         | None -> Error.type_error "Function `vcov` expects a model with a tidy coefficient table."
         | Some tidy_df ->
           let terms = Arrow_table.get_string_column tidy_df.arrow_table "term" in
           let n = Array.length terms in
           
           (* Try to get full vcov matrix *)
           let matrix_opt = match List.assoc_opt "vcov" model_data with
             | Some (VList rows) ->
                let mat = Array.make_matrix n n 0.0 in
                List.iteri (fun i (_, row) ->
                  match row with
                  | VVector v when i < n ->
                      Array.iteri (fun j x ->
                        if j < n then
                          match x with VFloat f -> mat.(i).(j) <- f | _ -> ()
                      ) v
                  | _ -> ()
                ) rows;
                Some mat
             | _ -> None
           in
           
           let final_mat = match matrix_opt with
             | Some m -> m
             | None ->
               (* Fallback: diagonal matrix from std_errors *)
               let ses = Arrow_table.get_float_column tidy_df.arrow_table "std_error" in
               let mat = Array.make_matrix n n 0.0 in
               for i = 0 to n - 1 do
                 match ses.(i) with
                 | Some se -> mat.(i).(i) <- se *. se
                 | None -> ()
               done;
               mat
           in
           
           (* Convert to DataFrame: term column + one column per term *)
           let term_col = ("term", Arrow_table.StringColumn terms) in
           let data_cols = List.mapi (fun j name_opt ->
             let name = match name_opt with Some s -> s | None -> Printf.sprintf "V%d" j in
             let col_data = Array.init n (fun i -> Some final_mat.(i).(j)) in
             (name, Arrow_table.FloatColumn col_data)
           ) (Array.to_list terms) in
           let table = Arrow_table.create (term_col :: data_cols) n in
           VDataFrame { arrow_table = table; group_keys = [] })
      | [VError _ as e] -> e
      | _ -> Error.type_error "Function `vcov` expects a model (Dict)."
    )) env
