(* src/packages/stats/residuals.ml *)
open Ast

(** residuals(data, model, type="response") — computes residuals for the given data. *)
(*
--# Model Residuals
--#
--# Computes residuals for a model given a dataset.
--#
--# @name residuals
--# @param data :: DataFrame Input data.
--# @param model :: Model The model object.
--# @param type :: String (Optional) Type of residuals = "response" (default) or "pearson".
--# @return :: DataFrame Columns = `actual`, `fitted`, `resid`.
--#
--# @details
--# Residuals represent the difference between observed data and model predictions.
--#
--# * **Response Residuals**: $r_i = y_i - \hat{y}_i$. These are raw residuals on the scale
--#   of the dependent variable. In GLMs, this corresponds to the difference on the 
--#   original scale (e.g., probability for binomial).
--#
--# * **Pearson Residuals**: $r_i^P = \frac{y_i - \hat{y}_i}{\sqrt{V(\hat{y}_i)}}$. These are 
--#   standardized by the variance function of the model. They are useful for detecting
--#   outliers and checking constant variance (homoscedasticity) in GLMs where variance 
--#   typically changes with the mean.
--#
--# @example
--#   res = residuals(mtcars, model)
--#   res_p = residuals(mtcars, model, type = "pearson")
--# @family stats
--# @export
*)
let register env =
  Env.add "residuals"
    (make_builtin_named ~name:"residuals" ~variadic:true 2 (fun args _env ->
      let parsed = match args with
        | (None, VDataFrame df) :: (None, VDict model) :: rest ->
            let t = match List.assoc_opt "type" (List.filter_map (fun (n, v) -> match n with Some s -> Some (s, v) | None -> None) rest) with
              | Some (VString s) -> String.lowercase_ascii s
              | _ -> "response"
            in
            Ok (df, model, t)
        | _ -> Error (Error.type_error "Function `residuals` expects (DataFrame, Model).")
      in
      
      match parsed with
      | Error e -> e
      | Ok (df, model, r_type) ->
        (* 1. Get fitted values using predict *)
        let predict_fn = match Env.find_opt "predict" _env with
          | Some (VBuiltin b) -> b.b_func
          | _ -> fun _ _ -> Error.type_error "Internal error: `predict` not found."
        in
        let fitted_v = predict_fn [(None, VDataFrame df); (None, VDict model)] (ref _env) in
        
        match fitted_v with
        | VVector fitted ->
          (* 2. Get actual values from response variable *)
          let response_name = match List.assoc_opt "formula" model with
            | Some (VFormula f) -> (match f.response with [name] -> Some name | _ -> None)
            | _ -> None
          in
          
          let actuals = match response_name with
            | Some name -> Arrow_table.get_float_column df.arrow_table name
            | None -> Array.make (Array.length fitted) None
          in
          
          let n = Array.length fitted in
          let resids = Array.init n (fun i ->
            match actuals.(i), fitted.(i) with
            | Some y, VFloat y_hat ->
                let raw = y -. y_hat in
                if r_type = "pearson" then
                  let family = match List.assoc_opt "_model_data" model with
                    | Some (VDict d) -> (match List.assoc_opt "family" d with Some (VString f) -> String.lowercase_ascii f | _ -> "gaussian")
                    | _ -> "gaussian"
                  in
                  let var_mu = match family with
                    | "binomial" -> y_hat *. (1.0 -. y_hat)
                    | "poisson"  -> y_hat
                    | "gamma"    -> y_hat *. y_hat
                    | _ -> 1.0
                  in
                  if var_mu > 0.0 then Some (raw /. sqrt var_mu) else Some raw
                else Some raw
            | _ -> None
          ) in
          
          let columns = [
            ("actual",  Arrow_table.FloatColumn actuals);
            ("fitted",  Arrow_table.FloatColumn (Array.map (function VFloat f -> Some f | _ -> None) fitted));
            ("resid",   Arrow_table.FloatColumn resids);
          ] in
          let table = Arrow_table.create columns n in
          VDataFrame { arrow_table = table; group_keys = [] }
        | VError e -> VError e
        | _ -> Error.type_error "Function `predict` did not return a Vector."
    )) env
