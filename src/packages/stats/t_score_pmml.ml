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
           (* 1. Write the DataFrame to a temporary Arrow file (for high fidelity) *)
           let tmp_in = Filename.temp_file "tlang_jpmml_in_" ".arrow" in
           let tmp_out = Filename.temp_file "tlang_jpmml_out_" ".arrow" in
           
           (match Arrow_io.write_ipc df.arrow_table tmp_in with
            | Error msg -> 
                Error.make_error FileError (Printf.sprintf "JPMML bridge: failed to write temporary input file: %s" msg)
            | Ok () ->
                (* 2. Invoke JPMML-evaluator. 
                   Assuming the evaluator JAR supports --pmml, --input, --output and ARROW format.
                   If not, we'd use CSV. *)
                let cmd = Printf.sprintf 
                  "java -jar %s --pmml %s --input %s --output %s --format arrow" 
                  (Filename.quote jar_path)
                  (Filename.quote pmml_path)
                  (Filename.quote tmp_in)
                  (Filename.quote tmp_out) 
                in
                (match Builder_utils.run_command_capture cmd with
                 | Ok (Unix.WEXITED 0, _) ->
                     (* 3. Read the result back *)
                     (match Arrow_io.read_ipc tmp_out with
                      | Ok table ->
                          (* Cleanup *)
                          (try Sys.remove tmp_in; Sys.remove tmp_out with _ -> ());
                          (* Extract the first column as a Vector if it has 1 column, 
                             or return the whole DataFrame if it has more (e.g. classification probabilities). *)
                          if Arrow_table.num_cols table = 1 then
                            (match Arrow_table.column_names table with
                             | name :: _ ->
                                 let col = Arrow_table.get_float_column table name in
                                 VVector (Array.map (fun f -> match f with Some v -> VFloat v | None -> VNA NAFloat) col)
                             | [] -> VNA NAGeneric)
                          else
                            VDataFrame { arrow_table = table; group_keys = [] }
                      | Error msg ->
                          Error.make_error FileError (Printf.sprintf "JPMML bridge: failed to read result: %s" msg))
                 | Ok (_, output) ->
                     Error.make_error RuntimeError (Printf.sprintf "JPMML bridge: execution failed:\n%s" output)
                 | Error msg ->
                     Error.make_error RuntimeError (Printf.sprintf "JPMML bridge: failed to launch JVM: %s" msg))))

let register env =
  Env.add "t_score_pmml"
    (make_builtin ~name:"t_score_pmml" 2 (fun args _env ->
      match args with
      | [VDataFrame df; VDict pairs] -> score_pmml_jpmml df (VDict pairs)
      | [VError _ as e; _] | [_; VError _ as e] -> e
      | [_; _] -> Error.type_error "t_score_pmml expects (DataFrame, Dict)."
      | _ -> Error.arity_error_named "t_score_pmml" 2 (List.length args)
    ))
    env
