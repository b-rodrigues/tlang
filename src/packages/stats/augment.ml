(* src/packages/stats/augment.ml *)
open Ast

(** augment(data, model) — augments a dataset with model-based predictions and residuals. *)
(*
--# Augment Data with Model Calculations
--#
--# Appends model predictions, residuals, and potentially diagnostic metrics to a dataset.
--#
--# @name augment
--# @param data :: DataFrame The dataset to augment.
--# @param model :: Model The model object.
--# @return :: DataFrame The original DataFrame with appended `fitted`, `resid`, etc.
--# @example
--#   aug = augment(mtcars, model)
--# @family stats
--# @export
*)
let register env =
  Env.add "augment"
    (make_builtin_named ~name:"augment" ~variadic:true 0 (fun args _env ->
      let named = List.filter_map (fun (n, v) -> match n with Some name -> Some (name, v) | None -> None) args in
      let positional = List.filter_map (fun (n, v) -> match n with None -> Some v | Some _ -> None) args in
      let data_v = match List.assoc_opt "data" named with
        | Some v -> Some v
        | None -> (match positional with v :: _ -> Some v | [] -> None)
      in
      let model_v = match List.assoc_opt "model" named with
        | Some v -> Some v
        | None -> (match positional with _ :: v :: _ -> Some v | _ -> (match positional with v :: _ when data_v <> Some v -> Some v | _ -> None))
      in
      match (data_v, model_v) with
      | (Some (VDataFrame df), Some (VDict model)) ->
        
        (* Priority 1: If it's a native T-Lang LM with pre-computed diagnostics in _model_data *)
        (match List.assoc_opt "_model_data" model with
         | Some (VDict m_data) ->
            let nrows = Arrow_table.num_rows df.arrow_table in
            let extract_float_array key =
              match List.assoc_opt key m_data with
              | Some (VVector arr) ->
                  Array.map (fun v -> match v with VFloat f -> Some f | _ -> None) arr
              | _ -> Array.make nrows None
            in
            
            let fitted_arr = extract_float_array "fitted_values" in
            let resid_arr = extract_float_array "residuals" in
            let hat_arr = extract_float_array "hat_values" in
            let cooksd_arr = extract_float_array "cooks_distance" in
            let std_resid_arr = extract_float_array "std_residuals" in
            let sigma_arr = extract_float_array "leave_one_out_sigma" in
            
            let table = df.arrow_table in
            let table = Arrow_table.add_column table "fitted" (Arrow_table.FloatColumn fitted_arr) in
            let table = Arrow_table.add_column table "resid" (Arrow_table.FloatColumn resid_arr) in
            let table = Arrow_table.add_column table "hat" (Arrow_table.FloatColumn hat_arr) in
            let table = Arrow_table.add_column table "sigma" (Arrow_table.FloatColumn sigma_arr) in
            let table = Arrow_table.add_column table "cooksd" (Arrow_table.FloatColumn cooksd_arr) in
            let table = Arrow_table.add_column table "std_resid" (Arrow_table.FloatColumn std_resid_arr) in
            VDataFrame { arrow_table = table; group_keys = df.group_keys }

         | _ ->
            (* Priority 2: Generic fallback using residuals() and predict() *)
            let residuals_fn = match Env.find_opt "residuals" _env with
              | Some (VBuiltin b) -> b.b_func
              | _ -> fun _ _ -> Error.type_error "Internal error: `residuals` not found."
            in
            let res_v = residuals_fn [(None, VDataFrame df); (None, VDict model)] (ref _env) in
            
            (match res_v with
             | VDataFrame res_df ->
                let fitted = Arrow_table.get_column res_df.arrow_table "fitted" in
                let resid  = Arrow_table.get_column res_df.arrow_table "resid" in
                
                let sigma = match List.assoc_opt "_model_data" model with
                  | Some (VDict d) -> (match List.assoc_opt "sigma" d with Some (VFloat f) -> f | _ -> 1.0)
                  | _ -> 1.0
                in
                
                let std_resid = match resid with
                  | Some (Arrow_table.FloatColumn data) ->
                      let n = Array.length data in
                      let r = Array.init n (fun i -> match data.(i) with Some e -> Some (e /. sigma) | None -> None) in
                      Some (Arrow_table.FloatColumn r)
                  | _ -> None
                in
                
                let new_cols = [
                  ("fitted", match fitted with Some c -> c | None -> Arrow_table.NAColumn 0);
                  ("resid",  match resid with Some c -> c | None -> Arrow_table.NAColumn 0);
                ] in
                let new_cols = match std_resid with
                  | Some c -> new_cols @ [("std_resid", c)]
                  | None -> new_cols
                in
                
                let orig_names = Arrow_table.column_names df.arrow_table in
                let combined_cols = List.map (fun name ->
                  (name, match Arrow_table.get_column df.arrow_table name with Some c -> c | None -> Arrow_table.NAColumn 0)
                ) orig_names in
                
                let final_table = Arrow_table.create (combined_cols @ new_cols) (Arrow_table.num_rows df.arrow_table) in
                VDataFrame { arrow_table = final_table; group_keys = df.group_keys }
                
             | VError e -> VError e
             | _ -> Error.type_error "Function `residuals` did not return a DataFrame."))
      | (Some (VError _ as e), _) | (_, Some (VError _ as e)) -> e
      | _ -> Error.type_error "Function `augment` expects (DataFrame, Model)."
    )) env
