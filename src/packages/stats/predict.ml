(* src/packages/stats/predict.ml *)
open Ast

(** predict(df, model) — performs prediction for a model.
    Standardized on JPMML as the primary execution authority.
    Native OCaml and ONNX scoring act as fallback for non-PMML models. *)
(*
--# Model Prediction
--#
--# Calculates predicted values for a model object.
--# Standardized on JPMML as the sole scoring authority for PMML models.
--# Native OCaml implementation is maintained for linear models and as a
--# validation fallback for trees.
--#
--# @name predict
--# @param data :: DataFrame The new data used for prediction.
--# @param model :: Model The model object (PMML, ONNX, or T-native).
--# @return :: Vector | DataFrame The predicted values. For JPMML-backed PMML models (e.g. classification), 
--#            this returns a DataFrame including probabilities. For regression or native models, 
--#            this returns a Vector of labels/values.
--# @family stats
--# @seealso lm, t_read_pmml, t_read_onnx
--# @export
*)

let register env =
  Env.add "predict"
    (make_builtin_named ~name:"predict" ~variadic:true 0 (fun args _env ->
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
      | (Some (VError _ as e), _) -> e
      | (_, Some (VError _ as e)) -> e
      | (Some (VDataFrame df), Some (VDict pairs)) ->
          
          (* 1. PMML Path has top-level priority (Standardized JPMML Authority) *)
          (match Pmml_utils.pmml_source_path (VDict pairs) with
           | Some _ -> T_score_pmml.score_pmml_jpmml df (VDict pairs)
           | None ->
          
          (* 2. Detect model type for native/ONNX fallback *)
          let model_type =
            match List.assoc_opt "model_type" pairs with
            | Some (VString s) | Some (VSymbol s) -> 
                let s = if String.length s > 0 && s.[0] = '^' then String.sub s 1 (String.length s - 1) else s in
                Some s
            | _ ->
                (match List.assoc_opt "class" pairs with
                 | Some (VString s) | Some (VSymbol s) -> 
                    let s = if String.length s > 0 && s.[0] = '^' then String.sub s 1 (String.length s - 1) else s in
                     Some s
                 | _ -> None)
          in
          
          (match model_type with
           | Some ("random_forest" | "forest") -> T_native_scoring.predict_forest_model df (VDict pairs)
           | Some ("decision_tree" | "tree") -> T_native_scoring.predict_tree_model df (VDict pairs)
           | Some ("xgboost" | "lightgbm") -> T_native_scoring.predict_boosted_model df (VDict pairs)
           | Some "onnx" -> T_native_scoring.predict_onnx_model df (VDict pairs)
           | _ ->
              (* Final fallback: Linear model coefficients *)
              let coeffs = match List.assoc_opt "coefficients" pairs with
                | Some (VDict c) -> c
                | _ -> []
              in
              if coeffs = [] then
                Error.make_error TypeError "Function `predict` expects a model with a `coefficients` dictionary or an attached JPMML source."
              else
                T_native_scoring.predict_linear_model df pairs))
      
      | (Some _, Some _) -> Error.type_error "Function `predict` expects (DataFrame, Model)."
      | _ -> Error.arity_error_named "predict" 2 (List.length positional + List.length named)
    )) env
