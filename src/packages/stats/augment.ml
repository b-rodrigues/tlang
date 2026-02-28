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
    (make_builtin ~name:"augment" 2 (fun args _env ->
      match args with
      | [VDataFrame df; VDict model] ->
        (* 1. Use residuals() to get fitted and resid *)
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
              ("fitted", match fitted with Some c -> c | None -> Arrow_table.NullColumn 0);
              ("resid",  match resid with Some c -> c | None -> Arrow_table.NullColumn 0);
            ] in
            let new_cols = match std_resid with
              | Some c -> new_cols @ [("std_resid", c)]
              | None -> new_cols
            in
            
            (* Combine with original columns *)
            let orig_names = Arrow_table.column_names df.arrow_table in
            let combined_cols = List.map (fun name ->
              (name, match Arrow_table.get_column df.arrow_table name with Some c -> c | None -> Arrow_table.NullColumn 0)
            ) orig_names in
            
            let final_table = Arrow_table.create (combined_cols @ new_cols) (Arrow_table.num_rows df.arrow_table) in
            VDataFrame { arrow_table = final_table; group_keys = df.group_keys }
            
         | VError e -> VError e
         | _ -> Error.type_error "Function `residuals` did not return a DataFrame.")
      | [VError _ as e; _] | [_; (VError _ as e)] -> e
      | _ -> Error.type_error "Function `augment` expects (DataFrame, Model)."
    )) env
