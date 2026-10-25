open Ast

let get_pmml_evaluator_jar () =
  match Sys.getenv_opt "T_JPMML_EVALUATOR_JAR" with
  | Some path when Sys.file_exists path -> Ok path
  | Some path ->
      Error (Printf.sprintf
               "JPMML evaluator JAR not found at `%s`. T ships this JAR at `<t-lang>/share/java/jpmml-evaluator.jar`. The `t-lang` input for this project is too old; point it at a version that ships the JAR."
               path)
  | None ->
      Error "T_JPMML_EVALUATOR_JAR environment variable not set. T sets it in pipeline node builds and in generated project shells. Update your Nix environment."

(* The evaluator needs a JVM. T_JPMML_JAVA names one explicitly (generated
   project shells and the dev shell set it to their `jre`); otherwise use
   `java` from PATH. The lookup is done here so a missing JVM produces a named
   error instead of a shell "command not found" from inside the bridge. *)
let find_on_path name =
  match Sys.getenv_opt "PATH" with
  | None -> None
  | Some path ->
      List.find_map
        (fun dir ->
          if dir = "" then None
          else
            let candidate = Filename.concat dir name in
            if Sys.file_exists candidate then Some candidate else None)
        (String.split_on_char ':' path)

(* Quote only when the path needs it, so a plain store path stays readable. *)
let as_command path = if String.contains path ' ' then Filename.quote path else path

let java_executable () =
  match Sys.getenv_opt "T_JPMML_JAVA" with
  | Some path when String.trim path <> "" ->
      if Sys.file_exists path then Ok (as_command path)
      else
        Error (Printf.sprintf
                 "JPMML: T_JPMML_JAVA points at `%s`, which does not exist. Unset it to use `java` from PATH, or point it at a JVM executable."
                 path)
  | _ ->
      (match find_on_path "java" with
       | Some path -> Ok (as_command path)
       | None ->
           Error "JPMML: `predict()` on a PMML model needs a Java runtime, and no `java` is on PATH. Add `jre` to [additional-tools] in tproject.toml, or set T_JPMML_JAVA to a java executable.")

let score_pmml_jpmml (df : dataframe) model_dict =
  match Pmml_utils.pmml_source_path model_dict with
  | None -> 
      Error.make_error RuntimeError "Function `predict` (PMML): model does not have an attached source PMML path. Native T PMML export is not yet implemented for JPMML-backed scoring."
  | Some pmml_path ->
      (match get_pmml_evaluator_jar () with
       | Error msg -> Error.make_error RuntimeError msg
       | Ok jar_path ->
         (match java_executable () with
          | Error msg -> Error.make_error RuntimeError msg
          | Ok java ->
             (* 1. Write the DataFrame to a temporary CSV file (standardized bridge format) *)
             let tmp_in = Filename.temp_file "tlang_jpmml_in_" ".csv" in
             let tmp_out = Filename.temp_file "tlang_jpmml_out_" ".csv" in
             let cleanup () =
               (try Sys.remove tmp_in with _ -> ());
               (try Sys.remove tmp_out with _ -> ())
             in
             Fun.protect
               ~finally:cleanup
               (fun () ->
                 match Arrow_io.write_csv df.arrow_table tmp_in with
                 | Error msg ->
                     Error.make_error FileError (Printf.sprintf "JPMML bridge: failed to write temporary input file: %s" msg)
                 | Ok () ->
                     (* 2. Invoke JPMML-evaluator.
                        Standardized on CSV format for maximum compatibility across JPMML versions. *)
                     let cmd = Printf.sprintf
                       "%s -jar %s --model %s --input %s --output %s"
                       java
                       (Filename.quote jar_path)
                       (Filename.quote pmml_path)
                       (Filename.quote tmp_in)
                       (Filename.quote tmp_out)
                     in
                     (match Builder_utils.run_command_capture cmd with
                      | Ok (Unix.WEXITED 0, _) ->
                          (* 3. Read the result back *)
                          (match Arrow_io.read_csv tmp_out with
                           | Ok table ->
                               let col_names = Arrow_table.column_names table in
                               if List.length col_names > 1 then
                                 VDataFrame { arrow_table = table; group_keys = [] }
                               else
                               (match col_names with
                                | name :: _ ->
                                    let col_type = Arrow_table.column_type table name in
                                    (match col_type with
                                     | Some (Arrow_table.ArrowFloat64 | Arrow_table.ArrowInt64) ->
                                         let col = Arrow_table.get_float_column table name in
                                         VVector (Array.map (fun f -> match f with Some v -> VFloat v | None -> VNA NAFloat) col)
                                     | Some Arrow_table.ArrowBoolean ->
                                         let col = Arrow_table.get_bool_column table name in
                                         VVector (Array.map (fun b -> match b with Some v -> VBool v | None -> VNA NABool) col)
                                     | _ ->
                                         let col = Arrow_table.get_string_column table name in
                                         VVector (Array.map (fun s -> match s with Some v -> VString v | None -> VNA NAString) col))
                                | [] -> VNA NAGeneric)
                           | Error msg ->
                               Error.make_error FileError (Printf.sprintf "JPMML bridge: failed to read result: %s" msg))
                      | Ok (_, output) ->
                          Error.make_error RuntimeError (Printf.sprintf "JPMML bridge: execution failed:\n%s" output)
                      | Error msg ->
                          Error.make_error RuntimeError (Printf.sprintf "JPMML bridge: failed to launch JVM: %s" msg)))))

let t_score_pmml =
  make_builtin ~name:"t_score_pmml" 2 (fun args _env ->
    match args with
    | [VDataFrame df; VDict pairs] -> score_pmml_jpmml df (VDict pairs)
    | [VError _ as e; _] | [_; VError _ as e] -> e
    | [_; _] -> Error.type_error "t_score_pmml expects (DataFrame, Dict)."
    | _ -> Error.arity_error_named "t_score_pmml" 2 (List.length args)
  )

let t_compare_scores_pmml =
  make_builtin ~name:"compare_native_vs_pmml_scores" 2 (fun args _env ->
    match args with
    | [VDataFrame df; VDict model_pairs] ->
        (match Pmml_utils.pmml_source_path (VDict model_pairs) with
         | None -> Error.make_error ValueError "compare_native_vs_pmml_scores: Model does not have a PMML source path."
         | Some _ ->
             let native_res =
               match List.assoc_opt "model_type" model_pairs with
               | Some (VString ("random_forest" | "forest")) -> T_native_scoring.predict_forest_model df (VDict model_pairs)
               | Some (VString ("decision_tree" | "tree")) -> T_native_scoring.predict_tree_model df (VDict model_pairs)
               | Some (VString ("xgboost" | "lightgbm")) -> T_native_scoring.predict_boosted_model df (VDict model_pairs)
               | _ -> Error.make_error TypeError "compare_native_vs_pmml_scores: Model type not supported for native scoring comparison."
             in
             (match native_res with
              | VError _ as e -> e
              | VVector native_vec ->
                  (match score_pmml_jpmml df (VDict model_pairs) with
                    | VError _ as e -> e
                    | VVector pmml_vec ->
                        if Array.length native_vec <> Array.length pmml_vec then
                          Error.make_error RuntimeError "Vector length mismatch between native and PMML scoring."
                        else
                          let diffs = ref 0 in
                          for i = 0 to Array.length native_vec - 1 do
                            match native_vec.(i), pmml_vec.(i) with
                            | VFloat f1, VFloat f2 -> if abs_float (f1 -. f2) > 1e-7 then incr diffs
                            | VString s1, VString s2 -> if s1 <> s2 then incr diffs
                            | VNA _, VNA _ -> ()
                            | VNA _, _ | _, VNA _ -> incr diffs
                            | _ -> ()
                          done;
                          VDict [
                            ("n_diffs", VInt !diffs);
                            ("match", VBool (!diffs = 0));
                            ("n_rows", VInt (Array.length native_vec));
                          ]
                    | VDataFrame df ->
                        (* Extraction logic for classification: find target column or take first. *)
                        let col_name = 
                          match List.assoc_opt "target" model_pairs with 
                          | Some (VString s) -> s 
                          | _ ->
                              match Arrow_table.column_names df.arrow_table with
                              | name :: _ -> name
                              | [] -> ""
                        in
                        (match Arrow_table.column_type df.arrow_table col_name with
                         | Some _ ->
                            let vec = match Arrow_table.column_type df.arrow_table col_name with
                              | Some (Arrow_table.ArrowFloat64 | Arrow_table.ArrowInt64) ->
                                  let col = Arrow_table.get_float_column df.arrow_table col_name in
                                  Array.map (fun f -> match f with Some v -> VFloat v | None -> VNA NAFloat) col
                              | Some Arrow_table.ArrowBoolean ->
                                  let col = Arrow_table.get_bool_column df.arrow_table col_name in
                                  Array.map (fun b -> match b with Some v -> VBool v | None -> VNA NABool) col
                              | _ ->
                                  let col = Arrow_table.get_string_column df.arrow_table col_name in
                                  Array.map (fun s -> match s with Some v -> VString v | None -> VNA NAString) col
                            in
                            (* Now we have a Vector, continue with comparison... *)
                            (* (Refactor note: extracting this into a helper would be cleaner) *)
                            let pmml_vec = vec in
                            if Array.length native_vec <> Array.length pmml_vec then
                              Error.make_error RuntimeError "Vector length mismatch between native and PMML scoring."
                            else
                              let diffs = ref 0 in
                              for i = 0 to Array.length native_vec - 1 do
                                match native_vec.(i), pmml_vec.(i) with
                                | VFloat f1, VFloat f2 -> if abs_float (f1 -. f2) > 1e-7 then incr diffs
                                | VString s1, VString s2 -> if s1 <> s2 then incr diffs
                                | VNA _, VNA _ -> ()
                                | VNA _, _ | _, VNA _ -> incr diffs
                                | _ -> ()
                              done;
                              VDict [
                                ("n_diffs", VInt !diffs);
                                ("match", VBool (!diffs = 0));
                                ("n_rows", VInt (Array.length native_vec));
                              ]
                         | None -> Error.make_error RuntimeError "JPMML bridge: result column not found.")
                    | _ -> Error.make_error RuntimeError "Expected Vector or DataFrame from JPMML bridge.")
              | _ -> Error.make_error RuntimeError "Expected Vector from native scorer."))
    | _ -> Error.arity_error_named "compare_native_vs_pmml_scores" 2 (List.length args))

let register env =
(*
--# Score a PMML model using JPMML
--#
--# Evaluates a PMML model against a DataFrame using the JPMML-evaluator library.
--# Requires a Java runtime and the JPMML-evaluator JAR to be available.
--#
--# @name t_score_pmml
--# @param df :: DataFrame The data to score.
--# @param model :: Dict The PMML model dictionary (loaded via `t_read_pmml`).
--# @return :: Vector | DataFrame The model predictions.
--# @family stats
--# @export
*)
  let env = Env.add "t_score_pmml" t_score_pmml env in
(*
--# Compare native T scoring vs JPMML scoring
--#
--# Validates the T-native implementation of model scoring (e.g. random forest)
--# against the reference JPMML evaluator. Returns a summary of differences.
--#
--# @name compare_native_vs_pmml_scores
--# @param df :: DataFrame The test data.
--# @param model :: Dict The model dictionary with both native and PMML metadata.
--# @return :: Dict A summary containing `n_diffs`, `match` (Bool), and `n_rows`.
--# @family stats
--# @export
*)
  let env = Env.add "compare_native_vs_pmml_scores" t_compare_scores_pmml env in
  env
