open Ast

(** glance(model) — returns a DataFrame of model-level statistics.
    Accepts a single model or a list of models. Equivalent to broom::glance(). *)
(*
--# Glance at Model Statistics
--#
--# Returns a tidy DataFrame of model-level statistics (e.g. R-squared, AIC, BIC).
--# Supports single model objects or labeled collections of models for comparison.
--#
--# When passed a list or dictionary of models, it stacks the results into a 
--# single DataFrame, automatically adding a 'model' column if labels are present.
--#
--# @name glance
--# @param x :: Model | List[Model] | Dict[String, Model] The model(s) to inspect.
--# @return :: DataFrame A tidy one-row-per-model summary of goodness-of-fit.
--# @example
--#   m1 = lm(mpg ~ wt, data = mtcars)
--#   glance(m1)
--# @example
--#   m2 = lm(mpg ~ hp + wt, data = mtcars)
--#   glance([Model_1: m1, Model_2: m2])
--# @family stats
--# @seealso lm, summary
--# @export
*)

let extract_stats_row pairs =
  match List.assoc_opt "_model_data" pairs with
  | Some (VDict model) ->
      let get_float key = match List.assoc_opt key model with
        | Some (VFloat f) -> Some f | _ -> None in
      let get_int key = match List.assoc_opt key model with
        | Some (VInt i) -> Some i | _ -> None in
      Some (get_float, get_int)
  | _ -> None

let register env =
  let glance_func args _env =
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
      Error.type_error "Function `glance` expects a model (Dict) or a List of models."
    else
      let rows = List.filter_map (fun (name, v) ->
        match v with
        | VDict pairs -> 
            (match extract_stats_row pairs with
             | Some (f, i) -> Some (name, f, i)
             | None -> None)
        | _ -> None
      ) models in
      
      if rows = [] then
        Error.type_error "Function `glance` found no valid model objects in the input."
      else
        let n = List.length rows in
        let mk_float_col getter =
          Arrow_table.FloatColumn (Array.of_list (List.map (fun (_, f, _) -> f getter) rows))
        in
        let mk_int_col getter =
          Arrow_table.FloatColumn (Array.of_list (List.map (fun (_, _, i) -> 
            match i getter with Some v -> Some (float_of_int v) | None -> None
          ) rows))
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
        ] in
        
        (* Add model name column if any models were named in the list *)
        let columns = 
          if List.exists (fun (name, _, _) -> Option.is_some name) rows then
            ("model", Arrow_table.StringColumn (Array.of_list (List.map (fun (name, _, _) -> name) rows))) :: columns
          else columns
        in

        let table = Arrow_table.create columns n in
        VDataFrame { arrow_table = table; group_keys = [] }
  in
  Env.add "glance" (make_builtin ~name:"glance" 1 glance_func) env
