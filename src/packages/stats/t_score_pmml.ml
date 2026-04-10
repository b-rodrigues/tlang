open Ast

let get_pmml_evaluator_jar () =
  match Sys.getenv_opt "T_JPMML_EVALUATOR_JAR" with
  | Some path -> Ok path
  | None -> 
      (* Fallback for development/testing if the env var isn't set yet *)
      let default = "/nix/store/dummy-jpmml-evaluator.jar" in
      if Sys.file_exists default then Ok default
      else Error "T_JPMML_EVALUATOR_JAR environment variable not set. Please update your Nix environment."

let score_pmml_jpmml (df : dataframe) model_dict =
  match Pmml_utils.pmml_source_path model_dict with
  | None -> 
      Error.make_error RuntimeError "Function `predict` (PMML): model does not have an attached source PMML path. Native T PMML export is not yet implemented for JPMML-backed scoring."
  | Some pmml_path ->
      (match get_pmml_evaluator_jar () with
       | Error msg -> Error.make_error RuntimeError msg
       | Ok jar_path ->
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
                       "java -jar %s --model %s --input %s --output %s"
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
                          Error.make_error RuntimeError (Printf.sprintf "JPMML bridge: failed to launch JVM: %s" msg))))

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
                           | VFloat f1, VFloat f2 ->
                               if abs_float (f1 -. f2) > 1e-7 then incr diffs
                           | VString s1, VString s2 ->
                               if s1 <> s2 then incr diffs
                           | VNA _, VNA _ -> ()
                           | VNA _, _ | _, VNA _ -> incr diffs
                           | _ -> ()
                         done;
                         VDict [
                           ("n_diffs", VInt !diffs);
                           ("match", VBool (!diffs = 0));
                           ("n_rows", VInt (Array.length native_vec));
                         ]
                   | _ -> Error.make_error RuntimeError "Expected Vector from JPMML bridge.")
              | _ -> Error.make_error RuntimeError "Expected Vector from native scorer."))
    | _ -> Error.arity_error_named "compare_native_vs_pmml_scores" 2 (List.length args))

let register env =
  let env = Env.add "t_score_pmml" t_score_pmml env in
  let env = Env.add "compare_native_vs_pmml_scores" t_compare_scores_pmml env in
  env
