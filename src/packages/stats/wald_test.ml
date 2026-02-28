(* src/packages/stats/wald_test.ml *)
open Ast

(** wald_test(model, terms: ["wt", "hp"]) — performs a joint Wald test on a subset of coefficients. *)
(*
--# Joint Wald Test
--#
--# Tests a null hypothesis that a subset of coefficients are jointly equal to zero.
--#
--# @name wald_test
--# @param model :: Model The model object.
--# @param terms :: List[String] The coefficient names to test.
--# @param value :: Float (Optional) The null value to test against. Defaults to 0.0.
--# @return :: DataFrame A one-row DataFrame with the test statistic and p-value.
--# @example
--#   wald_test(model, terms: ["wt", "hp"])
--# @family stats
--# @export
*)
let register env =
  Env.add "wald_test"
    (make_builtin_named ~name:"wald_test" ~variadic:true 0 (fun args _env ->
      let named = List.filter_map (fun (n, v) -> match n with Some name -> Some (name, v) | None -> None) args in
      let positional = List.filter_map (fun (n, v) -> match n with None -> Some v | Some _ -> None) args in
      
      let model_v = match List.assoc_opt "model" named with
        | Some v -> Some v
        | None -> (match positional with v :: _ -> Some v | [] -> None)
      in
      
      let terms_v = match List.assoc_opt "terms" named with
        | Some v -> Some v
        | None -> (match positional with _ :: v :: _ -> Some v | _ -> None)
      in
      
      let null_val = match List.assoc_opt "value" named with
        | Some (VFloat f) -> f
        | Some (VInt i) -> float_of_int i
        | _ -> 0.0
      in
      
      match (model_v, terms_v) with
      | (Some (VDict model), Some v) ->
          let test_terms = match v with
            | VString s -> [s]
            | VList l -> List.filter_map (fun (_, x) -> match x with VString s -> Some s | _ -> None) l
            | VVector v -> Array.to_list (Array.map (function VString s -> s | _ -> "") v) |> List.filter ((<>) "")
            | _ -> []
          in
          
          if test_terms = [] then
            Error.value_error "wald_test: 'terms' must be a list of coefficient names."
          else begin
            match List.assoc_opt "_tidy_df" model with
            | Some (VDataFrame tidy_df) ->
              let all_terms = Arrow_table.get_string_column tidy_df.arrow_table "term" |> Array.to_list |> List.filter_map (fun x -> x) in
              let estimates = Arrow_table.get_float_column tidy_df.arrow_table "estimate" in
              
              let model_data = match List.assoc_opt "_model_data" model with Some (VDict d) -> d | _ -> model in
              let full_vcov = match List.assoc_opt "vcov" model_data with
                | Some (VList rows) ->
                    let n = List.length all_terms in
                    let mat = Array.make_matrix n n 0.0 in
                    List.iteri (fun i (_, row) ->
                      match row with
                      | VVector v when i < n ->
                          Array.iteri (fun j x -> if j < n then match x with VFloat f -> mat.(i).(j) <- f | _ -> ()) v
                      | _ -> ()
                    ) rows;
                    Some mat
                | _ -> None
              in
              
              (match full_vcov with
               | None -> Error.type_error "wald_test: full variance-covariance matrix required but not found in model."
               | Some mat ->
                   (* 2. Find indices of tested terms *)
                   let indices = List.filter_map (fun term ->
                     let idx = ref (-1) in
                     List.iteri (fun i t -> if t = term then idx := i) all_terms;
                     if !idx = -1 then None else Some !idx
                   ) test_terms in
                   
                   if List.length indices <> List.length test_terms then
                     Error.value_error "wald_test: some terms not found in model coefficients."
                   else begin
                     let q = List.length indices in
                     let beta_q = Array.init q (fun i -> 
                       let idx = List.nth indices i in
                       match estimates.(idx) with Some f -> f -. null_val | None -> 0.0
                     ) in
                     let vcov_q = Array.init q (fun i ->
                       Array.init q (fun j ->
                         let idx_i = List.nth indices i in
                         let idx_j = List.nth indices j in
                         mat.(idx_i).(idx_j)
                       )
                     ) in
                     
                     (* 3. W = beta' * inv(V) * beta *)
                     match Math_utils.solve_and_invert vcov_q beta_q with
                     | None -> Error.value_error "wald_test: sub-matrix of vcov is singular."
                     | Some (inv_v_beta, _) ->
                         let w_stat = Math_utils.dot_product beta_q inv_v_beta in
                         
                         let family = match List.assoc_opt "family" model_data with Some (VString s) -> s | _ -> "gaussian" in
                         let df_resid = match List.assoc_opt "df_residual" model_data with Some (VInt i) -> i | _ -> 0 in
                         
                         let statistic, p_val, test_type =
                           if family = "gaussian" && df_resid > 0 then
                             let f_stat = w_stat /. float_of_int q in
                             (f_stat, 1.0 -. Distributions.pf f_stat q df_resid, "F")
                           else
                             (w_stat, 1.0 -. Distributions.pchisq w_stat q, "chi_square")
                         in
                         
                         (* 4. Return results *)
                         let columns = [
                           ("terms", Arrow_table.StringColumn [| Some (String.concat ", " test_terms) |]);
                           ("statistic", Arrow_table.FloatColumn [| Some statistic |]);
                           ("df", Arrow_table.FloatColumn [| Some (float_of_int q) |]);
                           ("p_value", Arrow_table.FloatColumn [| Some p_val |]);
                           ("test_type", Arrow_table.StringColumn [| Some test_type |]);
                         ] in
                         let table = Arrow_table.create columns 1 in
                         VDataFrame { arrow_table = table; group_keys = [] }
                   end)
            | _ -> Error.type_error "wald_test: expected a model object with coefficients."
          end
      | _ -> Error.type_error "Function `wald_test` expects (Model, terms: List[String])."
    )) env
