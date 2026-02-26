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

    while not (Xmlm.eoi i) do
      match Xmlm.input i with
      | `El_start ((_, "RegressionModel"), _) ->
          found_model := true
      | `El_start ((_, "RegressionTable"), attrs) ->
          found_table := true;
          intercept := (match find_attr "intercept" attrs with Some s -> float_of_string s | None -> 0.0)
      | `El_start ((_, "NumericPredictor"), attrs) ->
          let name = match find_attr "name" attrs with Some s -> s | None -> "" in
          let coef = match find_attr "coefficient" attrs with Some s -> float_of_string s | None -> 0.0 in
          if name <> "" then coeffs := (name, VFloat coef) :: !coeffs
      | _ -> ()
    done;
    close_in ic;

    if not !found_model then Error "No <RegressionModel> found in PMML"
    else if not !found_table then Error "No <RegressionTable> found in PMML"
    else
        let coeffs_dict = VDict (("(Intercept)", VFloat !intercept) :: !coeffs) in
        Ok (VDict [
          ("coefficients", coeffs_dict);
          ("class", VString "lm");
          ("model_type", VString "regression");
        ])
  with exn -> 
    Error (Printf.sprintf "PMML Parse Error: %s" (Printexc.to_string exn))
