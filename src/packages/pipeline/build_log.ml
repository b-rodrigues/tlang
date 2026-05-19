open Ast

let find_latest_matching_log_path (p : Ast.pipeline_result) =
  let logs = Builder.get_logs () in
  let try_log log_file =
    let full_path = Filename.concat Builder.pipeline_dir log_file in
    match Builder.read_log full_path with
    | Ok entries when Builder_read_node.pipeline_matches_logged_entries p entries -> Some full_path
    | _ -> None
  in
  List.find_map try_log logs

(*
--# Retrieve Build Log for Pipeline
--#
--# Returns the `BuildLog` of the latest Nix build for the given pipeline.
--# Includes node-level status records, total duration, failed node names, and `out_path`.
--#
--# @name build_log
--# @param p :: Pipeline The pipeline to retrieve logs for.
--# @return :: BuildLog
--# @family pipeline
--# @export
*)
let build_log_fn args _env =
  match args with
  | [VPipeline p] ->
      (match find_latest_matching_log_path p with
       | Some log_path -> Builder.parse_json_log_to_vbuildlog log_path
       | None -> Error.make_error FileError "No matching build log found for the pipeline. Run build_pipeline(p) first.")
  | [_] -> Error.type_error "Function `build_log` expects a Pipeline."
  | _ -> Error.arity_error_named "build_log" 1 (List.length args)

(*
--# Tabulate Build Log as DataFrame
--#
--# Returns a DataFrame with columns `name`, `status`, and `duration` summarizing the build nodes.
--#
--# @name build_log_to_frame
--# @param log :: BuildLog The build log to tabulate.
--# @return :: DataFrame
--# @family pipeline
--# @export
*)
let build_log_to_frame_fn args _env =
  match args with
  | [VBuildLog bl] ->
      let nrows = List.length bl.bl_nodes in
      let arr_name = Array.make nrows None in
      let arr_status = Array.make nrows None in
      let arr_duration = Array.make nrows None in
      List.iteri (fun i item ->
        match item with
        | VDict fields ->
            let name = match List.assoc_opt "name" fields with Some (VString s) -> Some s | _ -> None in
            let status = match List.assoc_opt "status" fields with Some (VString s) -> Some s | _ -> None in
            let duration = match List.assoc_opt "duration" fields with Some (VFloat f) -> Some f | _ -> None in
            arr_name.(i) <- name;
            arr_status.(i) <- status;
            arr_duration.(i) <- duration;
        | _ -> ()
      ) bl.bl_nodes;
      let columns = [
        ("name", Arrow_table.StringColumn arr_name);
        ("status", Arrow_table.StringColumn arr_status);
        ("duration", Arrow_table.FloatColumn arr_duration);
      ] in
      let arrow_table = Arrow_table.create columns nrows in
      VDataFrame { arrow_table; group_keys = [] }
  | [_] -> Error.type_error "Function `build_log_to_frame` expects a BuildLog."
  | _ -> Error.arity_error_named "build_log_to_frame" 1 (List.length args)

(*
--# Gather Pipeline Node Errors
--#
--# Gathers all `VError` values from computed artifacts of a built pipeline.
--#
--# @name collect_errors
--# @param p :: Pipeline The built pipeline to gather errors from.
--# @return :: List
--# @family pipeline
--# @export
*)
let collect_errors_fn args _env =
  match args with
  | [VPipeline p] ->
      (match find_latest_matching_log_path p with
       | None -> VList []
       | Some _ ->
           let node_names = List.map fst p.p_nodes in
           let errors = List.filter_map (fun name ->
             try
               match Builder_read_node.read_node name with
               | VNodeResult { v = VError _ as err; _ } -> Some (None, err)
               | VError _ as err -> Some (None, err)
               | _ -> None
             with _ -> None
           ) node_names in
           VList errors)
  | [_] -> Error.type_error "Function `collect_errors` expects a Pipeline."
  | _ -> Error.arity_error_named "collect_errors" 1 (List.length args)

let register env =
  let env = Env.add "build_log" (make_builtin ~name:"build_log" 1 build_log_fn) env in
  let env = Env.add "build_log_to_frame" (make_builtin ~name:"build_log_to_frame" 1 build_log_to_frame_fn) env in
  let env = Env.add "collect_errors" (make_builtin ~name:"collect_errors" 1 collect_errors_fn) env in
  env
