open Ast

(** fit_stats(model) — returns a DataFrame of model-level statistics.
    Accepts a single model or a list of models. *)
(*
--# Model Goodness-of-Fit Statistics
--#
--# Returns a tidy DataFrame of model-level statistics (e.g. R-squared, AIC, BIC).
--# Supports single model objects or labeled collections of models for comparison.
--#
--# When passed a list or dictionary of models, it stacks the results into a 
--# single DataFrame, automatically adding a 'model' column if labels are present.
--#
--# @name fit_stats
--# @param x :: Model | List[Model] | Dict[String, Model] The model(s) to inspect.
--# @return :: DataFrame A tidy one-row-per-model summary of goodness-of-fit.
--# @example
--#   m1 = lm(mpg ~ wt, data = mtcars)
--#   fit_stats(m1)
--# @example
--#   m2 = lm(mpg ~ hp + wt, data = mtcars)
--#   fit_stats([Model_1: m1, Model_2: m2])
--# @family stats
--# @seealso lm, summary
--# @export
*)

type stats_row = {
  name: string option;
  get_float: string -> float option;
  get_int: string -> int option;
  get_string: string -> string option;
}

let value_list = function
  | VList items -> List.map (fun (_, v) -> v) items
  | _ -> []

let assoc_string key pairs =
  match List.assoc_opt key pairs with
  | Some (VString s) -> Some s
  | _ -> None

let assoc_int key pairs =
  match List.assoc_opt key pairs with
  | Some (VInt i) -> Some i
  | _ -> None

let rec fields_from_predicate v =
  match v with
  | VDict pairs ->
      (match assoc_string "type" pairs with
       | Some "simple" | Some "set" ->
           (match assoc_string "field" pairs with Some f -> [f] | None -> [])
       | Some "compound" ->
           (match List.assoc_opt "predicates" pairs with
            | Some preds ->
                preds
                |> value_list
                |> List.concat_map fields_from_predicate
            | None -> [])
       | _ -> [])
  | _ -> []

let rec fields_from_node v =
  match v with
  | VDict pairs ->
      let pred_fields =
        match List.assoc_opt "predicate" pairs with
        | Some pred -> fields_from_predicate pred
        | None -> []
      in
      let child_fields =
        match List.assoc_opt "children" pairs with
        | Some children ->
            children
            |> value_list
            |> List.concat_map fields_from_node
        | None -> []
      in
      pred_fields @ child_fields
  | _ -> []

let unique_fields fields =
  let seen = Hashtbl.create 16 in
  List.filter (fun f ->
    if Hashtbl.mem seen f then false else (Hashtbl.add seen f (); true)
  ) fields

let extract_stats_row pairs =
  let model_type = assoc_string "model_type" pairs in
  let model_data = match List.assoc_opt "_model_data" pairs with
    | Some (VDict model) -> Some model
    | _ -> None
  in
  match model_type, model_data with
  | None, None -> None
  | _ ->
      let extra_int =
        match model_type with
        | Some "random_forest" ->
            let n_trees =
              match List.assoc_opt "n_trees" pairs with
              | Some (VInt i) -> Some i
              | _ ->
                  (match List.assoc_opt "forest" pairs with
                   | Some (VDict forest_pairs) ->
                       (match List.assoc_opt "trees" forest_pairs with
                        | Some trees -> Some (List.length (value_list trees))
                        | _ -> None)
                   | _ -> None)
            in
            let n_features =
              match List.assoc_opt "forest" pairs with
              | Some (VDict forest_pairs) ->
                  (match List.assoc_opt "trees" forest_pairs with
                   | Some trees ->
                       let fields =
                         trees
                         |> value_list
                         |> List.concat_map (function
                            | VDict tree_pairs ->
                                (match List.assoc_opt "root" tree_pairs with
                                 | Some root -> fields_from_node root
                                 | None -> [])
                            | _ -> [])
                       in
                       Some (List.length (unique_fields fields))
                   | _ -> None)
              | _ -> None
            in
            ("n_trees", n_trees, "n_features", n_features)
        | Some "decision_tree" ->
            let n_features =
              match List.assoc_opt "tree" pairs with
              | Some (VDict tree_pairs) ->
                  (match List.assoc_opt "root" tree_pairs with
                   | Some root ->
                       let fields = fields_from_node root |> unique_fields in
                       Some (List.length fields)
                   | None -> None)
              | _ -> None
            in
            ("n_trees", Some 1, "n_features", n_features)
        | Some ("xgboost" | "lightgbm") ->
            let n_trees =
              match List.assoc_opt "boosted_model" pairs with
              | Some (VDict ensemble_pairs) ->
                  (match List.assoc_opt "models" ensemble_pairs with
                   | Some (VList model_entries) ->
                       let total =
                         List.fold_left (fun acc (_, entry) ->
                           match entry with
                           | VDict entry_pairs ->
                               (match List.assoc_opt "forest" entry_pairs with
                                | Some (VDict forest_pairs) ->
                                    (match List.assoc_opt "trees" forest_pairs with
                                     | Some trees -> acc + List.length (value_list trees)
                                     | _ -> acc)
                                | _ -> acc)
                           | _ -> acc
                         ) 0 model_entries
                       in
                       Some total
                   | _ -> None)
              | _ -> None
            in
            let n_features =
              match List.assoc_opt "boosted_model" pairs with
              | Some (VDict ensemble_pairs) ->
                  (match List.assoc_opt "models" ensemble_pairs with
                   | Some (VList model_entries) ->
                       let all_fields =
                         List.concat_map (fun (_, entry) ->
                           match entry with
                           | VDict entry_pairs ->
                               (match List.assoc_opt "forest" entry_pairs with
                                | Some (VDict forest_pairs) ->
                                    (match List.assoc_opt "trees" forest_pairs with
                                     | Some trees ->
                                         trees
                                         |> value_list
                                         |> List.concat_map (function
                                            | VDict tree_pairs ->
                                                (match List.assoc_opt "root" tree_pairs with
                                                 | Some root -> fields_from_node root
                                                 | None -> [])
                                            | _ -> [])
                                     | _ -> [])
                                | _ -> [])
                           | _ -> []
                         ) model_entries
                       in
                       Some (List.length (unique_fields all_fields))
                   | _ -> None)
              | _ -> None
            in
            ("n_trees", n_trees, "n_features", n_features)
        | _ -> ("n_trees", None, "n_features", None)
      in
      let get_float key =
        match model_data with
        | Some model ->
            (match List.assoc_opt key model with
             | Some (VFloat f) -> Some f
             | _ -> None)
        | None -> None
      in
      let get_int key =
        let (trees_key, trees_val, feats_key, feats_val) = extra_int in
        if key = trees_key then trees_val
        else if key = feats_key then feats_val
        else
          match model_data with
          | Some model ->
              (match List.assoc_opt key model with
               | Some (VInt i) -> Some i
               | _ -> None)
          | None -> None
      in
      let get_string key =
        match key with
        | "model_type" -> model_type
        | "mining_function" -> assoc_string "mining_function" pairs
        | _ ->
            (match model_data with
             | Some model ->
                 (match List.assoc_opt key model with
                  | Some (VString s) -> Some s
                  | _ -> None)
             | None -> None)
      in
      Some { name = None; get_float; get_int; get_string }

let build_stats_dataframe rows =
  let n = List.length rows in
  let mk_float_col getter =
    Arrow_table.FloatColumn (Array.of_list (List.map (fun row -> row.get_float getter) rows))
  in
  let mk_int_col getter =
    Arrow_table.FloatColumn (Array.of_list (List.map (fun row ->
      match row.get_int getter with Some v -> Some (float_of_int v) | None -> None
    ) rows))
  in
  let mk_string_col getter =
    Arrow_table.StringColumn (Array.of_list (List.map (fun row -> row.get_string getter) rows))
  in
  let columns = [
    ("r_squared",     mk_float_col "r_squared");
    ("adj_r_squared", mk_float_col "adj_r_squared");
    ("sigma",         mk_float_col "sigma");
    ("statistic",     mk_float_col "f_statistic");
    ("p_value",       mk_float_col "f_p_value");
    ("df",            mk_int_col "df_model");
    ("logLik",        mk_float_col "log_lik");
    ("AIC",           mk_float_col "aic");
    ("BIC",           mk_float_col "bic");
    ("deviance",      mk_float_col "deviance");
    ("df_residual",   mk_int_col "df_residual");
    ("nobs",          mk_int_col "nobs");
    ("n_trees",       mk_int_col "n_trees");
    ("n_features",    mk_int_col "n_features");
    ("model_type",    mk_string_col "model_type");
    ("mining_function", mk_string_col "mining_function");
  ] in
  let columns =
    if List.exists (fun row -> Option.is_some row.name) rows then
      ("model", Arrow_table.StringColumn (Array.of_list (List.map (fun row -> row.name) rows))) :: columns
    else columns
  in
  let table = Arrow_table.create columns n in
  VDataFrame { arrow_table = table; group_keys = [] }

let summary_metrics_for_model pairs =
  match extract_stats_row pairs with
  | Some row -> Some (build_stats_dataframe [row])
  | None -> None

let register env =
  let fit_stats_func args _env =
    match args with
    | [VError _ as e] -> e
    | _ ->
    let models = match args with
      | [VList items] -> items
      | [VDict pairs] -> 
          if List.mem_assoc "_model_data" pairs then
            [(None, VDict pairs)] (* Single model object *)
          else
            (* A dictionary of models, e.g., [m1: model_a, m2: model_b] *)
            List.map (fun (k, v) -> (Some k, v)) pairs
      | _ -> []
    in
    if models = [] then
      Error.type_error "Function `fit_stats` expects a model (Dict) or a List of models."
    else
      let rows = List.filter_map (fun (name, v) ->
        match v with
        | VDict pairs ->
            (match extract_stats_row pairs with
             | Some row -> Some { row with name }
             | None -> None)
        | _ -> None
      ) models in

      if rows = [] then
        Error.type_error "Function `fit_stats` found no valid model objects in the input."
      else
        build_stats_dataframe rows
  in
  Env.add "fit_stats" (make_builtin ~name:"fit_stats" 1 fit_stats_func) env
