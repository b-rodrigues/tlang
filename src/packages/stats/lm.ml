open Ast

type design_term = {
  name : string;
  values : float array;
}

module StringSet = Set.Make (String)

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
    ("vcov", VList (Array.to_list (Array.map (fun row ->
      (None, VVector (Array.map (fun x -> VFloat x) row))
    ) result.vcov)));
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
    ("model_type", VString "lm");
    ("mining_function", VString "regression");
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

let float_array_of_numeric_column col_name = function
  | Arrow_table.FloatColumn values ->
      let n = Array.length values in
      let result = Array.make n 0.0 in
      let rec loop i =
        if i = n then Ok result
        else
          match values.(i) with
          | Some f -> result.(i) <- f; loop (i + 1)
          | None ->
              Error
                (Error.type_error
                   (Printf.sprintf
                      "Function `lm` column `%s` must be numeric or categorical without NA values."
                      col_name))
      in
      loop 0
  | Arrow_table.IntColumn values ->
      let n = Array.length values in
      let result = Array.make n 0.0 in
      let rec loop i =
        if i = n then Ok result
        else
          match values.(i) with
          | Some v -> result.(i) <- float_of_int v; loop (i + 1)
          | None ->
              Error
                (Error.type_error
                   (Printf.sprintf
                      "Function `lm` column `%s` must be numeric or categorical without NA values."
                      col_name))
      in
      loop 0
  | _ ->
      Error
        (Error.type_error
           (Printf.sprintf
              "Function `lm` column `%s` must be numeric or categorical without NA values."
              col_name))

let unique_levels values =
  values
  |> Array.fold_left (fun (seen, acc) value ->
       if StringSet.mem value seen then
         (seen, acc)
       else
         (StringSet.add value seen, value :: acc)
     ) (StringSet.empty, [])
  |> snd
  |> List.rev

let categorical_design_terms col_name = function
  | Arrow_table.DictionaryColumn (indices, levels, _) ->
      let has_na = Array.exists Option.is_none indices in
      if has_na then
        Error
          (Error.type_error
             (Printf.sprintf
                "Function `lm` column `%s` must be numeric or categorical without NA values."
                col_name))
      else
      let present = Hashtbl.create 8 in
      Array.iter (function
        | Some idx -> Hashtbl.replace present idx ()
        | None -> ()
      ) indices;
      let active_levels =
        levels
        |> List.mapi (fun idx level -> (idx, level))
        |> List.filter_map (fun (idx, level) ->
             if Hashtbl.mem present idx then Some (idx, level) else None)
      in
      let encoded_levels =
        match active_levels with
        | [] | [ _ ] -> []
        | _ :: rest -> rest
      in
      let rec build acc = function
        | [] -> Ok (List.rev acc)
        | (level_idx, level_name) :: rest ->
            let n = Array.length indices in
            let result = Array.make n 0.0 in
            let rec fill row_idx =
              if row_idx = n then
                build ({ name = col_name ^ level_name; values = result } :: acc) rest
              else
                match indices.(row_idx) with
                | Some idx ->
                    result.(row_idx) <- if idx = level_idx then 1.0 else 0.0;
                    fill (row_idx + 1)
                | None ->
                    Error
                      (Error.type_error
                         (Printf.sprintf
                            "Function `lm` column `%s` must be numeric or categorical without NA values."
                            col_name))
            in
            fill 0
      in
      build [] encoded_levels
  | Arrow_table.StringColumn values ->
      let n = Array.length values in
      let string_values = Array.make n "" in
      let rec collect i =
        if i = n then Ok string_values
        else
          match values.(i) with
          | Some value -> string_values.(i) <- value; collect (i + 1)
          | None ->
              Error
                (Error.type_error
                   (Printf.sprintf
                      "Function `lm` column `%s` must be numeric or categorical without NA values."
                      col_name))
      in
      (match collect 0 with
       | Error _ as err -> err
       | Ok string_values ->
           let encoded_levels =
             match unique_levels string_values with
             | [] | [ _ ] -> []
             | _ :: rest -> rest
           in
           let terms =
             List.map (fun level_name ->
               {
                 name = col_name ^ level_name;
                 values = Array.init n (fun i ->
                   if String.equal string_values.(i) level_name then 1.0 else 0.0);
               }
             ) encoded_levels
           in
           Ok terms)
  | _ ->
      Error
        (Error.type_error
           (Printf.sprintf
              "Function `lm` column `%s` must be numeric or categorical without NA values."
              col_name))

let predictor_terms_for_column arrow_table col_name =
  match Arrow_table.get_column arrow_table col_name with
  | None ->
      Error
        (Error.make_error KeyError
           (Printf.sprintf "Column `%s` not found in DataFrame." col_name))
  | Some col ->
      match Arrow_table.column_type_of col with
      | Arrow_table.ArrowFloat64 | Arrow_table.ArrowInt64 ->
          (match float_array_of_numeric_column col_name col with
           | Ok values -> Ok [ { name = col_name; values } ]
           | Error _ as err -> err)
      | Arrow_table.ArrowString | Arrow_table.ArrowDictionary ->
          categorical_design_terms col_name col
      | _ ->
          Error
            (Error.type_error
               (Printf.sprintf
                  "Function `lm` column `%s` must be numeric or categorical without NA values."
                  col_name))

let multiply_design_terms left_terms right_terms =
  List.concat_map (fun left ->
    List.map (fun right ->
      let n = Array.length left.values in
      {
        name = left.name ^ ":" ^ right.name;
        values = Array.init n (fun i -> left.values.(i) *. right.values.(i));
      }
    ) right_terms
  ) left_terms

let formula_term_parts term =
  if String.contains term ':'
  then String.split_on_char ':' term
  else [ term ]

let predictor_terms_for_formula_term arrow_table term =
  let parts = formula_term_parts term in
  let rec expand acc = function
    | [] ->
        (match acc with
         | [] -> Error (Error.internal_error "lm() produced an empty predictor term.")
         | terms :: rest ->
             Ok (List.fold_left multiply_design_terms terms rest))
    | part :: rest ->
        (match predictor_terms_for_column arrow_table part with
         | Error _ as err -> err
         | Ok terms -> expand (acc @ [terms]) rest)
  in
  expand [] parts

(*
--# Linear Model
--#
--# Fits a linear regression model using Ordinary Least Squares (OLS).
--#
--# @name lm
--# @param data :: DataFrame The data to use.
--# @param formula :: Formula The model formula (e.g., mpg ~ wt + hp).
--# @return :: Model A model object containing coefficients, residuals, and statistics.
--# @example
--#   model = lm(mtcars, mpg ~ wt + hp)
--#   summary(model)
--# @family stats
--# @seealso summary, fit_stats, add_diagnostics
--# @export
*)
let register env =
  Env.add "lm"
    (make_builtin_named ~name:"lm" ~variadic:true 0 (fun args _env ->
      let named = List.filter_map (fun (n, v) ->
        match n with Some name -> Some (name, v) | None -> None
      ) args in
      let positional = List.filter_map (fun (n, v) ->
        match n with None -> Some v | Some _ -> None
      ) args in
      (* Get required arguments: try named first, fall back to positional *)
      (* Standard R convention: lm(formula, data) *)
      let data_val = match List.assoc_opt "data" named with
        | Some v -> Some v
        | None -> (match positional with v :: _ -> Some v | [] -> None)
      in
      let formula_val = match List.assoc_opt "formula" named with
        | Some v -> Some v
        | None -> (match positional with _ :: v :: _ -> Some v | _ -> (match positional with v :: _ when data_val <> Some v -> Some v | _ -> None))
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
                     (* Verify all base columns exist, including those referenced by interaction terms. *)
                     let missing =
                       predictors
                       |> List.find_map (fun term ->
                           formula_term_parts term
                           |> List.find_opt (fun col -> not (Arrow_table.has_column df.arrow_table col)))
                     in
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
                                 let xs_result = List.fold_left (fun acc term ->
                                   match acc with
                                   | Error e -> Error e
                                   | Ok xs_terms ->
                                       (match predictor_terms_for_formula_term df.arrow_table term with
                                        | Error e -> Error e
                                        | Ok predictor_terms -> Ok (List.rev_append predictor_terms xs_terms))
                                 ) (Ok []) predictors in
                                 let xs_result = Result.map List.rev xs_result in
                                 (match xs_result with
                                  | Error e -> e
                                  | Ok xs_terms ->
                                      if xs_terms = [] then
                                        Error.value_error
                                          "Function `lm` requires at least one varying predictor term after factor encoding."
                                      else
                                        (match Arrow_owl_bridge.detect_collinearity
                                                 (List.map (fun term -> (term.name, term.values)) xs_terms) with
                                         | Some detail ->
                                             Error.value_error
                                               (Printf.sprintf
                                                  "Function `lm` detected collinearity: %s."
                                                  detail)
                                         | None ->
                                             let xs_arrays = List.map (fun term -> term.values) xs_terms in
                                             let predictor_names = List.map (fun term -> term.name) xs_terms in
                                             let ys = y_view.arr in
                                             (match Arrow_owl_bridge.linreg_multi xs_arrays ys predictor_names with
                                              | None ->
                                                  Error.value_error
                                                    "Function `lm` detected collinearity: design matrix is singular."
                                              | Some result ->
                                                  build_model_value result formula_v data_v))))))
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
