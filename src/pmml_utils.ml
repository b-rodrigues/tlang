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
    let found_model = ref false in
    let found_table = ref false in

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
               | Some ("tStatistic" | "statistic"), Some v -> p.statistic <- Some v
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
              let name = match find_attr "name" attrs with Some s -> s | None -> "" in
              let coef = match get_float_attr "coefficient" attrs with Some v -> v | None -> 0.0 in
              let p = { name; estimate = coef; 
                        std_error = get_float_attr "stdError" attrs; 
                        statistic = get_float_attr "tStatistic" attrs; 
                        p_value = get_float_attr "pValue" attrs } in
              parse_predictor_body p;
              coeffs := p :: !coeffs;
              table_loop ()
          | `El_start ((_, "Extension"), attrs) ->
              (match find_attr "name" attrs, get_float_attr "value" attrs with
               | Some ("standardError" | "stdError"), Some v -> int_p.std_error <- Some v
               | Some ("tStatistic" | "statistic"), Some v -> int_p.statistic <- Some v
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
        | `El_start ((_, "RegressionModel"), attrs) ->
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
                let intercept_val = match get_float_attr "intercept" attrs with Some v -> v | None -> 0.0 in
                let p = { name = "(Intercept)"; estimate = intercept_val; 
                          std_error = get_float_attr "stdError" attrs;
                          statistic = get_float_attr "tStatistic" attrs;
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
            loop ()
        | `El_start _ -> loop ()
        | `El_end | `Data _ | `Dtd _ -> loop ()
    in
    loop ();
    close_in ic;

    if not !found_model then Error "No <RegressionModel> found in PMML"
    else if not !found_table then Error "No <RegressionTable> found in PMML"
    else
        let all_preds = match !intercept with
          | Some p -> p :: List.rev !coeffs
          | None -> List.rev !coeffs
        in
        let num_preds = List.length all_preds in

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
        let model_data = VDict [
          ("r_squared", (match !r2 with Some v -> VFloat v | None -> VNull));
          ("adj_r_squared", (match !adj_r2 with Some v -> VFloat v | None -> VNull));
          ("aic", (match !aic with Some v -> VFloat v | None -> VNull));
          ("bic", (match !bic with Some v -> VFloat v | None -> VNull));
          ("sigma", (match !sigma with Some v -> VFloat v | None -> VNull));
          ("nobs", (match !nobs with Some v -> VInt v | None -> VInt 0));
          ("df_model", VInt (max 0 (num_preds - 1)));
        ] in

        let coefficients_dict = VDict (List.map (fun p -> (p.name, VFloat p.estimate)) all_preds) in
        let std_errors_dict = VDict (List.map (fun p -> (p.name, match p.std_error with Some v -> VFloat v | None -> VNull)) all_preds) in

        Ok (VDict [
          ("_tidy_df", tidy_df);
          ("_model_data", model_data);
          ("coefficients", coefficients_dict);
          ("std_errors", std_errors_dict);
          ("class", VString "lm");
          ("model_type", VString "regression");
          ("_display_keys", VList [
            (None, VString "coefficients");
            (None, VString "std_errors");
            (None, VString "class");
            (None, VString "model_type");
          ]);
        ])
  with exn -> 
    Error (Printf.sprintf "PMML Parse Error: %s" (Printexc.to_string exn))
