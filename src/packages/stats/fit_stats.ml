open Ast

(** glance(model) — returns a DataFrame of model-level statistics.
    Accepts a single model or a list of models. Equivalent to broom::glance(). *)

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
      | [VDict pairs] -> [(None, VDict pairs)]
      | _ -> []
    in
    if models = [] then
      Error.type_error "Function `glance` expects a model (Dict) or a List of models."
    else
      let rows = List.filter_map (fun (name, v) ->
        match v with
        | VDict pairs -> 
            let keys = List.map fst pairs in
            let () = Printf.printf "glance(DEBUG): found keys: [%s]\n" (String.concat ", " keys) in
            (match extract_stats_row pairs with
             | Some (f, i) -> Some (name, f, i)
             | None -> 
                 let () = Printf.printf "glance(DEBUG): extract_stats_row failed for %s\n" (Option.value ~default:"unnamed" name) in
                 None)
        | _ -> 
            let () = Printf.printf "glance(DEBUG): item not a Dict\n" in
            None
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
  let env = Env.add "glance" (make_builtin ~name:"glance" 1 glance_func) env in
  Env.add "fit_stats" (make_builtin ~name:"fit_stats" 1 glance_func) env
