(* src/pmml_utils.ml *)
open Ast

type predictor_info = {
  name: string;
  estimate: float;
  mutable std_error: float option;
  mutable statistic: float option;
  mutable p_value: float option;
}

(** PMML parser for RegressionModel.
    Extracts coefficients, standard errors, and model stats into a full T linear model object. *)
let read_pmml path =
  try
    let ic = open_in path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let i = Xmlm.make_input (`Channel ic) in
    
    let find_attr name attrs =
      List.find_map (fun ((_, n), v) -> if n = name then Some v else None) attrs
    in
    let get_float_attr name attrs =
      match find_attr name attrs with
      | Some s -> (try Some (float_of_string s) with _ -> None)
      | None -> None
    in

    let intercept = ref None in
    let coeffs = ref [] in
    let r2 = ref None in
    let adj_r2 = ref None in
    let aic = ref None in
    let bic = ref None in
    let sigma = ref None in
    let nobs = ref None in
    let f_statistic = ref None in
    let f_p_value = ref None in
    let log_lik = ref None in
    let deviance_ = ref None in
    let df_residual = ref None in
    let glm_stats = ref None in
    let found_model = ref false in
    let found_table = ref false in
    let response_name = ref None in
    let predictors = ref [] in

    let ignore_element () =
      let rec skip depth =
        if Xmlm.eoi i then ()
        else match Xmlm.input i with
        | `El_start _ -> skip (depth + 1)
        | `El_end -> if depth = 0 then () else skip (depth - 1)
        | _ -> skip depth
      in skip 0
    in

    let parse_predictor_body p =
      let rec pred_loop () =
        if Xmlm.eoi i then ()
        else match Xmlm.peek i with
          | `El_start ((_, "Extension"), attrs) ->
              let _ = Xmlm.input i in
              (match find_attr "name" attrs, get_float_attr "value" attrs with
               | Some ("standardError" | "stdError"), Some v -> p.std_error <- Some v
               | Some ("tStatistic" | "zStatistic" | "statistic"), Some v -> p.statistic <- Some v
               | Some ("pValue" | "p-value"), Some v -> p.p_value <- Some v
               | _ -> ());
              ignore_element ();
              pred_loop ()
          | `El_end -> let _ = Xmlm.input i in ()
          | `El_start _ -> let _ = Xmlm.input i in ignore_element (); pred_loop ()
          | `Data _ | `Dtd _ -> let _ = Xmlm.input i in pred_loop ()
      in pred_loop ()
    in

    let parse_table_body (int_p : predictor_info) =
      let rec table_loop () =
        if Xmlm.eoi i then ()
        else match Xmlm.input i with
          | `El_start ((_, "NumericPredictor"), attrs) ->
              let name = match find_attr "name" attrs with
                | Some s -> s
                | None -> failwith "Required PMML attribute 'name' missing in <NumericPredictor>"
              in
              let coef = match get_float_attr "coefficient" attrs with
                | Some v -> v
                | None -> failwith "Required PMML attribute 'coefficient' missing in <NumericPredictor>"
              in
              let p = { name; estimate = coef; 
                        std_error = get_float_attr "stdError" attrs; 
                        statistic = (match get_float_attr "tStatistic" attrs with Some v -> Some v | None -> get_float_attr "zStatistic" attrs); 
                        p_value = get_float_attr "pValue" attrs } in
              parse_predictor_body p;
              coeffs := p :: !coeffs;
              table_loop ()
          | `El_start ((_, "Extension"), attrs) ->
            (match find_attr "name" attrs, get_float_attr "value" attrs with
               | Some ("standardError" | "stdError"), Some v -> int_p.std_error <- Some v
               | Some ("tStatistic" | "zStatistic" | "statistic"), Some v -> int_p.statistic <- Some v
               | Some ("pValue" | "p-value"), Some v -> int_p.p_value <- Some v
               | _ -> ());
              ignore_element ();
              table_loop ()
          | `El_end -> ()
          | `El_start _ -> ignore_element (); table_loop ()
          | `Data _ | `Dtd _ -> table_loop ()
      in table_loop ()
    in

    let rec loop () =
      if Xmlm.eoi i then ()
      else match Xmlm.input i with
        | `El_start ((_, ("RegressionModel" | "GeneralRegressionModel" | "MiningModel")), attrs) ->
            found_model := true;
            (match get_float_attr "r_squared" attrs with Some v -> r2 := Some v 
             | None -> (match get_float_attr "r2" attrs with Some v -> r2 := Some v | _ -> ()));
            (match get_float_attr "adj_r_squared" attrs with Some v -> adj_r2 := Some v 
             | None -> (match get_float_attr "adj-r2" attrs with Some v -> adj_r2 := Some v | _ -> ()));
            (match get_float_attr "aic" attrs with Some v -> aic := Some v | _ -> ());
            (match get_float_attr "bic" attrs with Some v -> bic := Some v | _ -> ());
            loop ()
        | `El_start ((_, "RegressionTable"), attrs) ->
            if not !found_table then begin
                found_table := true;
                let intercept_val = match get_float_attr "intercept" attrs with
                  | Some v -> v
                  | None -> failwith "Required PMML attribute 'intercept' missing in <RegressionTable>"
                in
                let p = { name = "(Intercept)"; estimate = intercept_val; 
                          std_error = get_float_attr "stdError" attrs;
                          statistic = (match get_float_attr "tStatistic" attrs with Some v -> Some v | None -> get_float_attr "zStatistic" attrs);
                          p_value = get_float_attr "pValue" attrs } in
                intercept := Some p;
                parse_table_body p
            end;
            loop ()
        | `El_start ((_, "PredictiveModelQuality"), attrs) ->
            (match get_float_attr "r2" attrs with Some v -> r2 := Some v | _ -> ());
            (match get_float_attr "adj-r2" attrs with Some v -> adj_r2 := Some v | _ -> ());
            (match get_float_attr "aic" attrs with Some v -> aic := Some v | _ -> ());
            (match get_float_attr "bic" attrs with Some v -> bic := Some v | _ -> ());
            (match get_float_attr "sigma" attrs with Some v -> sigma := Some v | _ -> ());
            (match get_float_attr "nobs" attrs with Some v -> nobs := (try Some (int_of_float v) with _ -> None) | _ -> ());
            (match get_float_attr "fStatistic" attrs with Some v -> f_statistic := Some v | _ -> ());
            (match get_float_attr "fPValue" attrs with Some v -> f_p_value := Some v | _ -> ());
            (match get_float_attr "logLik" attrs with Some v -> log_lik := Some v | _ -> ());
            (match get_float_attr "deviance" attrs with Some v -> deviance_ := Some v | _ -> ());
            (match get_float_attr "dfResidual" attrs with Some v -> df_residual := (try Some (int_of_float v) with _ -> None) | _ -> ());
            loop ()
        | `El_start ((_, "MiningField"), attrs) ->
            (match find_attr "name" attrs, find_attr "usageType" attrs with
             | Some name, Some "target" -> response_name := Some name
             | Some name, Some "active" -> predictors := name :: !predictors
             | _ -> ());
            ignore_element ();
            loop ()
        | `El_start ((_, "Extension"), attrs) ->
            if List.exists (fun ((_, n), v) -> n = "name" && v = "GLMStats") attrs then
              (match List.find_map (fun ((_, n), v) -> if n = "value" then Some v else None) attrs with
               | Some json_s -> 
                   (try 
                      let json = Yojson.Safe.from_string json_s in
                      glm_stats := Some json
                    with _ -> ())
               | None -> ());
            loop ()
        | `El_start _ -> loop ()
        | `El_end | `Data _ | `Dtd _ -> loop ()
    in
    loop ();

    if not !found_model then Error "No <RegressionModel> or <GeneralRegressionModel> found in PMML"
    else

        let is_glm = Option.is_some !glm_stats in
        
        (* If no coefficients were found in PMML tags, try extracting them from GLMStats JSON extension *)
        if !coeffs = [] && Option.is_none !intercept then begin
          match !glm_stats with
          | Some (`Assoc stats) ->
              (match List.assoc_opt "coefficients" stats with
               | Some (`Assoc c_map) ->
                   let extract_p name obj =
                      let open Yojson.Safe.Util in
                      let get_f n = 
                        match obj |> member n with 
                        | `Float f -> Some f 
                        | `String s -> float_of_string_opt s 
                        | `Int i -> Some (float_of_int i)
                        | _ -> None 
                      in
                      { name; 
                        estimate = (match get_f "estimate" with Some v -> v | None -> 0.0);
                        std_error = get_f "std_error";
                        statistic = get_f "statistic";
                        p_value = get_f "p_value" }
                   in
                   let json_coeffs = List.map (fun (name, obj) -> extract_p name obj) c_map in
                   let (ints, others) = List.partition (fun p -> p.name = "(Intercept)" || p.name = "(intercept)") json_coeffs in
                   coeffs := List.rev others;
                   if ints <> [] then intercept := Some (List.hd ints)
               | _ -> ())
          | _ -> ()
        end;

        let all_preds = match !intercept with
          | Some p -> p :: List.rev !coeffs
          | None -> List.rev !coeffs
        in
        let num_preds = List.length all_preds in
        let model_class = if is_glm then "glm" else "lm" in

        (* 1. Build Tidy DataFrame (broom::tidy) *)
        let term_col      = Arrow_table.StringColumn (Array.of_list (List.map (fun p -> Some p.name) all_preds)) in
        let estimate_col  = Arrow_table.FloatColumn (Array.of_list (List.map (fun p -> Some p.estimate) all_preds)) in
        let std_error_col = Arrow_table.FloatColumn (Array.of_list (List.map (fun p -> p.std_error) all_preds)) in
        let statistic_col = Arrow_table.FloatColumn (Array.of_list (List.map (fun p -> p.statistic) all_preds)) in
        let p_value_col   = Arrow_table.FloatColumn (Array.of_list (List.map (fun p -> p.p_value) all_preds)) in

        let tidy_table = Arrow_table.create [
          ("term", term_col);
          ("estimate", estimate_col);
          ("std_error", std_error_col);
          ("statistic", statistic_col);
          ("p_value", p_value_col);
        ] num_preds in
        let tidy_df = VDataFrame { arrow_table = tidy_table; group_keys = [] } in

        (* 2. Build Model Data (broom::glance) *)
        let base_model_data = [
          ("r_squared", (match !r2 with Some v -> VFloat v | None -> VNull));
          ("adj_r_squared", (match !adj_r2 with Some v -> VFloat v | None -> VNull));
          ("aic", (match !aic with Some v -> VFloat v | None -> VNull));
          ("bic", (match !bic with Some v -> VFloat v | None -> VNull));
          ("sigma", (match !sigma with Some v -> VFloat v | None -> VNull));
          ("nobs", (match !nobs with Some v -> VInt v | None -> VNull));
          ("df_model", VInt (max 0 (num_preds - 1)));
          ("f_statistic", (match !f_statistic with Some v -> VFloat v | None -> VNull));
          ("f_p_value", (match !f_p_value with Some v -> VFloat v | None -> VNull));
          ("log_lik", (match !log_lik with Some v -> VFloat v | None -> VNull));
          ("deviance", (match !deviance_ with Some v -> VFloat v | None -> VNull));
          ("df_residual", (match !df_residual with Some v -> VInt v | None -> VNull));
        ] in

        let model_data_list = match !glm_stats with
          | None -> base_model_data
          | Some json ->
              let open Yojson.Safe.Util in
              let get_field name = 
                match json |> member name with
                | `String s -> (try VFloat (float_of_string s) with _ -> VString s)
                | `Int n -> VInt n
                | `Float f -> VFloat f
                | _ -> VNull
              in
              base_model_data @ [
                ("family", get_field "family");
                ("link", get_field "link");
                ("null_deviance", get_field "null_deviance");
                ("null_deviance_df", get_field "null_deviance_df");
                ("residual_deviance", get_field "residual_deviance");
                ("residual_deviance_df", get_field "residual_deviance_df");
                ("dispersion", get_field "dispersion");
              ]
        in
        let model_data = VDict model_data_list in

        let coefficients_dict = VDict (List.map (fun p -> (p.name, VFloat p.estimate)) all_preds) in
        let std_errors_dict = VDict (List.map (fun p -> (p.name, match p.std_error with Some v -> VFloat v | None -> VNull)) all_preds) in

        let display_keys = [
          (None, VString "coefficients");
          (None, VString "std_errors");
          (None, VString "class");
          (None, VString "model_type");
        ] in
        let display_keys = if is_glm then 
          display_keys @ [ (None, VString "family"); (None, VString "link") ]
          else display_keys in

        Ok (VDict [
          ("_tidy_df", tidy_df);
          ("_model_data", model_data);
          ("coefficients", coefficients_dict);
          ("std_errors", std_errors_dict);
          ("class", VString model_class);
          ("model_type", VString "regression");
          ("family", (match !glm_stats with Some j -> (match Yojson.Safe.Util.member "family" j with `String s -> VString s | _ -> VNull) | None -> VNull));
          ("link", (match !glm_stats with Some j -> (match Yojson.Safe.Util.member "link" j with `String s -> VString s | _ -> VNull) | None -> VNull));
          ("formula", (match !response_name with
            | Some r -> VFormula { response = [r]; predictors = List.rev !predictors; raw_lhs = Value VNull; raw_rhs = Value VNull }
            | None -> VNull));
          ("_display_keys", VList display_keys);
        ])
    ) (* end Fun.protect *)
  with exn -> 
    Error (Printf.sprintf "PMML Parse Error: %s" (Printexc.to_string exn))
