(* src/pmml_utils.ml *)
open Ast

(** Minimal PMML parser for RegressionModel.
    Extracts coefficients and intercept into a T VDict. *)
let read_pmml path =
  try
    let ic = open_in path in
    let i = Xmlm.make_input (`Channel ic) in
    
    let find_attr name attrs =
      List.find_map (fun ((_, n), v) -> if n = name then Some v else None) attrs
    in

    let intercept = ref 0.0 in
    let coeffs = ref [] in
    let found_model = ref false in
    let found_table = ref false in

    let rec loop () =
      if Xmlm.eoi i then ()
      else begin
        (match Xmlm.input i with
        | `El_start ((_, "RegressionModel"), _) ->
            found_model := true
        | `El_start ((_, "RegressionTable"), attrs) ->
            found_table := true;
            (match find_attr "intercept" attrs with
             | Some s -> intercept := float_of_string s
             | None -> failwith "Missing 'intercept' attribute in <RegressionTable>")
        | `El_start ((_, "NumericPredictor"), attrs) ->
            let name =
              match find_attr "name" attrs with
              | Some s -> s
              | None -> failwith "Required PMML attribute 'name' missing in NumericPredictor"
            in
            let coef =
              match find_attr "coefficient" attrs with
              | Some s -> float_of_string s
              | None -> failwith "Required PMML attribute 'coefficient' missing in NumericPredictor"
            in
            coeffs := (name, VFloat coef) :: !coeffs
        | `El_start _ | `El_end | `Data _ | `Dtd _ -> ());
        loop ()
      end
    in
    loop ();
    close_in ic;

    if not !found_model then Error "No <RegressionModel> found in PMML"
    else if not !found_table then Error "No <RegressionTable> found in PMML"
    else
        let term_names = "(Intercept)" :: List.rev_map fst !coeffs in
        let coefficients = !intercept :: List.rev_map (function (_, VFloat f) -> f | _ -> 0.0) !coeffs in
        let p = List.length term_names in

        (* 1. Build Tidy DataFrame (broom::tidy) *)
        let term_col = Arrow_table.StringColumn (Array.of_list (List.map (fun n -> Some n) term_names)) in
        let estimate_col = Arrow_table.FloatColumn (Array.of_list (List.map (fun c -> Some c) coefficients)) in
        let empty_col = Arrow_table.FloatColumn (Array.make p None) in

        let tidy_table = Arrow_table.create [
          ("term", term_col);
          ("estimate", estimate_col);
          ("std_error", empty_col);
          ("statistic", empty_col);
          ("p_value", empty_col);
        ] p in
        let tidy_df = VDataFrame { arrow_table = tidy_table; group_keys = [] } in

        (* 2. Build Model Data (broom::glance) *)
        let model_data = VDict [
          ("nobs", VInt 0);
          ("df_model", VInt (p - 1));
        ] in

        let coefficients_dict = VDict (List.map2 (fun n c -> (n, VFloat c)) term_names coefficients) in

        Ok (VDict [
          ("_tidy_df", tidy_df);
          ("_model_data", model_data);
          ("coefficients", coefficients_dict);
          ("class", VString "lm");
          ("model_type", VString "regression");
          ("_display_keys", VList [
            (None, VString "coefficients");
            (None, VString "class");
            (None, VString "model_type");
          ]);
        ])
  with exn -> 
    Error (Printf.sprintf "PMML Parse Error: %s" (Printexc.to_string exn))
