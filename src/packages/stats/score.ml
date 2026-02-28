(* src/packages/stats/score.ml *)
open Ast

(** score(data, model) — calculates performance metrics for a model on new data. *)
(*
--# Model Scoring
--#
--# Calculates various performance metrics (RMSE, MAE, R-squared, etc.) for a model on a dataset.
--#
--# @name score
--# @param data :: DataFrame The dataset to score.
--# @param model :: Model The model object.
--# @return :: DataFrame A one-row DataFrame with metrics.
--#
--# @details
--# Calculates standard performance metrics to evaluate model fit on new or existing data:
--#
--# * **RMSE (Root Mean Square Error)**: $\sqrt{\frac{1}{n}\sum(y_i - \hat{y}_i)^2}$. 
--#   Penalizes larger errors more heavily.
--# * **MAE (Mean Absolute Error)**: $\frac{1}{n}\sum|y_i - \hat{y}_i|$. 
--#   A more robust metric that is less sensitive to outliers.
--# * **R2 (R-squared)**: The proportion of variance explained by the model.
--#
--# For **Binomial** models, it also calculates **Log-Loss** (Cross-Entropy).
--#
--# @example
--#   metrics = score(test_data, model)
--# @family stats
--# @export
*)
let register env =
  Env.add "score"
    (make_builtin ~name:"score" 2 (fun args _env ->
      match args with
      | [VDataFrame df; VDict model] ->
        (* 1. Use residuals() to get actual, fitted, resid *)
        let residuals_fn = match Env.find_opt "residuals" _env with
          | Some (VBuiltin b) -> b.b_func
          | _ -> fun _ _ -> Error.type_error "Internal error: `residuals` not found."
        in
        let res_v = residuals_fn [(None, VDataFrame df); (None, VDict model)] (ref _env) in
        
        (match res_v with
         | VDataFrame res_df ->
            let actuals = Arrow_table.get_float_column res_df.arrow_table "actual" in
            let fitted  = Arrow_table.get_float_column res_df.arrow_table ".fitted" in
            let resids  = Arrow_table.get_float_column res_df.arrow_table ".resid" in
            
            let valid_resids = List.filter_map (fun x -> x) (Array.to_list resids) in
            let nv = float_of_int (List.length valid_resids) in
            
            if nv = 0.0 then Error.value_error "Function `score` found no valid observations."
            else
              let mae = List.fold_left (fun acc r -> acc +. Float.abs r) 0.0 valid_resids /. nv in
              let mse = List.fold_left (fun acc r -> acc +. r *. r) 0.0 valid_resids /. nv in
              let rmse = sqrt mse in
              
              (* R-squared *)
              let r_sq = 
                let ys = List.filter_map (fun x -> x) (Array.to_list actuals) in
                if List.length ys < 2 then 0.0
                else
                  let mean_y = List.fold_left (+.) 0.0 ys /. float_of_int (List.length ys) in
                  let ss_tot = List.fold_left (fun acc y -> acc +. (y -. mean_y) *. (y -. mean_y)) 0.0 ys in
                  let ss_res = List.fold_left (fun acc r -> acc +. r *. r) 0.0 valid_resids in
                  if ss_tot = 0.0 then 1.0 else 1.0 -. ss_res /. ss_tot
              in
              
              let metrics = ref [
                ("rmse", Arrow_table.FloatColumn [| Some rmse |]);
                ("mae",  Arrow_table.FloatColumn [| Some mae |]);
                ("r2",   Arrow_table.FloatColumn [| Some r_sq |]);
              ] in
              
              (* Family-specific metrics *)
              let model_data = match List.assoc_opt "_model_data" model with Some (VDict d) -> d | _ -> [] in
              let family = match List.assoc_opt "family" model_data with Some (VString f) -> String.lowercase_ascii f | _ -> "gaussian" in
              
              if family = "binomial" then begin
                let log_loss = 
                  let y_true = actuals in
                  let y_prob = fitted in
                  let sum_ll = ref 0.0 in
                  let count = ref 0 in
                  for i = 0 to Array.length y_true - 1 do
                    match y_true.(i), y_prob.(i) with
                    | Some y, Some p ->
                        let p_eps = Float.max 1e-15 (Float.min (1.0 -. 1e-15) p) in
                        sum_ll := !sum_ll -. (y *. log p_eps +. (1.0 -. y) *. log (1.0 -. p_eps));
                        incr count
                    | _ -> ()
                  done;
                  if !count > 0 then Some (!sum_ll /. float_of_int !count) else None
                in
                metrics := !metrics @ [("log_loss", Arrow_table.FloatColumn [| log_loss |])]
              end;
              
              let table = Arrow_table.create !metrics 1 in
              VDataFrame { arrow_table = table; group_keys = [] }
              
         | VError e -> VError e
         | _ -> Error.type_error "Function `residuals` did not return a DataFrame.")
      | [VError _ as e; _] | [_; (VError _ as e)] -> e
      | _ -> Error.type_error "Function `score` expects (DataFrame, Model)."
    )) env
