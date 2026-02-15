open Ast

(** Build a tidy DataFrame from an lm_result and return it as the model VDict *)
let build_model_value (result : Arrow_owl_bridge.lm_result)
    (formula_v : value) (data_v : value) : value =
  let p = Array.length result.coefficients in
  let nrows = p in
  (* Build tidy DataFrame columns *)
  let term_col = Arrow_table.StringColumn (
    Array.init nrows (fun i -> Some (List.nth result.term_names i))
  ) in
  let estimate_col = Arrow_table.FloatColumn (
    Array.init nrows (fun i -> Some result.coefficients.(i))
  ) in
  let std_error_col = Arrow_table.FloatColumn (
    Array.init nrows (fun i -> Some result.std_errors.(i))
  ) in
  let statistic_col = Arrow_table.FloatColumn (
    Array.init nrows (fun i -> Some result.t_statistics.(i))
  ) in
  let p_value_col = Arrow_table.FloatColumn (
    Array.init nrows (fun i -> Some result.p_values.(i))
  ) in
  let tidy_table = Arrow_table.create [
    ("term", term_col);
    ("estimate", estimate_col);
    ("std_error", std_error_col);
    ("statistic", statistic_col);
    ("p_value", p_value_col);
  ] nrows in
  let tidy_df = VDataFrame { arrow_table = tidy_table; group_keys = [] } in
  (* Model internals dict — used by fit_stats() and add_diagnostics() *)
  let n = result.nobs in
  let model_data = VDict [
    ("r_squared", VFloat result.r_squared);
    ("adj_r_squared", VFloat result.adj_r_squared);
    ("sigma", VFloat result.sigma);
    ("f_statistic", VFloat result.f_statistic);
    ("f_p_value", VFloat result.f_p_value);
    ("df_model", VInt result.df_model);
    ("df_residual", VInt result.df_residual);
    ("nobs", VInt result.nobs);
    ("log_lik", VFloat result.log_lik);
    ("aic", VFloat result.aic);
    ("bic", VFloat result.bic);
    ("deviance", VFloat result.deviance);
    ("residuals", VVector (Array.map (fun r -> VFloat r) result.residuals_arr));
    ("fitted_values", VVector (Array.map (fun f -> VFloat f) result.fitted_values));
    ("hat_values", VVector (Array.map (fun h -> VFloat h) result.hat_values));
    ("cooks_distance", VVector (Array.map (fun c -> VFloat c) result.cooks_distance));
    ("std_residuals", VVector (Array.map (fun s -> VFloat s) result.std_residuals));
    ("leave_one_out_sigma", VVector (Array.init n (fun i ->
      let hi = result.hat_values.(i) in
      let ei = result.residuals_arr.(i) in
      let n_f = float_of_int n in
      let p_f = float_of_int (Array.length result.coefficients) in
      let df_resid_f = n_f -. p_f in
      let ss_res = result.deviance in
      if df_resid_f > 1.0 && (1.0 -. hi) > 0.0 then
        let ss_i = (ss_res *. df_resid_f -. ei *. ei /. (1.0 -. hi)) /. (df_resid_f -. 1.0) in
        VFloat (sqrt (Float.abs ss_i))
      else VFloat result.sigma
    )));
  ] in

  (* Create coefficients dictionary *)
  let coef_pairs = List.map2 (fun name value ->
    (name, VFloat value)
  ) result.term_names (Array.to_list result.coefficients) in
  let coefficients_dict = VDict coef_pairs in

  (* Create standard errors dictionary *)
  let stderr_pairs = List.map2 (fun name value ->
    (name, VFloat value)
  ) result.term_names (Array.to_list result.std_errors) in
  let std_errors_dict = VDict stderr_pairs in

  (* Return VDict as a model object — prints formula + key stats *)
  VDict [
    ("_tidy_df", tidy_df);
    ("_model_data", model_data);
    ("_original_data", data_v);
    ("coefficients", coefficients_dict);
    ("std_errors", std_errors_dict);
    ("formula", formula_v);
    ("r_squared", VFloat result.r_squared);
    ("adj_r_squared", VFloat result.adj_r_squared);
    ("sigma", VFloat result.sigma);
    ("nobs", VInt result.nobs);
    ("_display_keys", VList [
      (None, VString "formula");
      (None, VString "coefficients");
      (None, VString "std_errors");
      (None, VString "r_squared");
      (None, VString "adj_r_squared");
      (None, VString "sigma");
      (None, VString "nobs");
    ]);
  ]

(*
--# Linear Model
--#
--# Fits a linear regression model using Ordinary Least Squares (OLS).
--#
--# @name lm
--# @param formula :: Formula The model formula (e.g., mpg ~ wt + hp).
--# @param data :: DataFrame The data to use.
--# @return :: Model A model object containing coefficients, residuals, and statistics.
--# @example
--#   model = lm(mpg ~ wt + hp, data: mtcars)
--#   summary(model)
--# @family stats
--# @seealso summary, fit_stats, add_diagnostics
--# @export
*)
let register env =
  Env.add "lm"
    (make_builtin_named ~variadic:true 0 (fun args _env ->
      let named = List.filter_map (fun (n, v) ->
        match n with Some name -> Some (name, v) | None -> None
      ) args in
      let positional = List.filter_map (fun (n, v) ->
        match n with None -> Some v | Some _ -> None
      ) args in
      (* Get required arguments: try named first, fall back to positional *)
      let data_val = match List.assoc_opt "data" named with
        | Some v -> Some v
        | None -> (match positional with v :: _ -> Some v | [] -> None)
      in
      let formula_val = match List.assoc_opt "formula" named with
        | Some v -> Some v
        | None -> (match positional with _ :: v :: _ -> Some v | _ -> None)
      in
      match (data_val, formula_val) with
      | (None, _) -> Error.make_error ArityError "Function `lm` missing required argument 'data'."
      | (_, None) -> Error.make_error ArityError "Function `lm` missing required argument 'formula'."
      | (Some data_v, Some formula_v) ->
        match (data_v, formula_v) with
        | (VDataFrame df, VFormula { response; predictors; _ }) ->
          (* Extract response variable name *)
          (match response with
           | [y_col] ->
             (* Extract predictor variable names (supports multiple) *)
             if predictors = [] then
               Error.value_error "Function `lm` right side of formula is empty."
             else begin
               (* Verify response column exists *)
               (match Arrow_table.get_column df.arrow_table y_col with
                | None ->
                    Error.make_error KeyError
                      (Printf.sprintf "Column `%s` not found in DataFrame." y_col)
                | Some _ ->
                  (* Verify all predictor columns exist *)
                  let missing = List.find_opt (fun col ->
                    not (Arrow_table.has_column df.arrow_table col)
                  ) predictors in
                  (match missing with
                   | Some col ->
                       Error.make_error KeyError
                         (Printf.sprintf "Column `%s` not found in DataFrame." col)
                   | None ->
                     let nrows = Arrow_table.num_rows df.arrow_table in
                     if nrows < 2 then
                       Error.value_error "Function `lm` requires at least 2 observations."
                     else
                       (* Extract numeric columns *)
                       (match Arrow_owl_bridge.numeric_column_to_owl df.arrow_table y_col with
                        | None ->
                          Error.type_error
                            "Function `lm` requires numeric columns without NA values."
                        | Some y_view ->
                          let xs_result = List.fold_left (fun acc col ->
                            match acc with
                            | Error e -> Error e
                            | Ok xs_views ->
                              match Arrow_owl_bridge.numeric_column_to_owl df.arrow_table col with
                              | None -> Error (Error.type_error
                                  (Printf.sprintf "Function `lm` column `%s` must be numeric without NA values." col))
                              | Some x_view -> Ok (xs_views @ [x_view])
                          ) (Ok []) predictors in
                          (match xs_result with
                           | Error e -> e
                           | Ok xs_views ->
                             let xs_arrays = List.map (fun (v : Arrow_owl_bridge.owl_view) -> v.arr) xs_views in
                             let ys = y_view.arr in
                             (match Arrow_owl_bridge.linreg_multi xs_arrays ys predictors with
                              | None ->
                                Error.value_error
                                  "Function `lm` cannot fit model: design matrix is singular."
                              | Some result ->
                                build_model_value result formula_v data_v)))))
             end
           | [] ->
               Error.value_error "Function `lm` left side of formula is empty."
           | _ ->
               Error.value_error
                 "Function `lm` only supports single response variable.")
        | (VDataFrame _, _) ->
            Error.type_error "Function `lm` 'formula' must be a Formula (use ~ operator)."
        | (_, _) ->
            Error.type_error "Function `lm` 'data' must be a DataFrame."
    ))
    env
