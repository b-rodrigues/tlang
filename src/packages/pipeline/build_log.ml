open Ast

let clean_and_truncate_message msg =
  let lines = String.split_on_char '\n' msg 
              |> List.map String.trim 
              |> List.filter (fun s -> s <> "") in
  let msg_line =
    match List.rev lines with
    | [] -> ""
    | last :: _ -> last
  in
  if String.length msg_line > 100 then
    String.sub msg_line 0 97 ^ "..."
  else
    msg_line

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
      let arr_path = Array.make nrows None in
      List.iteri (fun i item ->
        match item with
        | VDict fields ->
            let name = match List.assoc_opt "name" fields with Some (VString s) -> Some s | _ -> None in
            let status = match List.assoc_opt "status" fields with Some (VString s) -> Some s | _ -> None in
            let duration = match List.assoc_opt "duration" fields with Some (VFloat f) -> Some f | _ -> None in
            let path = match List.assoc_opt "path" fields with Some (VString s) -> Some s | _ -> None in
            arr_name.(i) <- name;
            arr_status.(i) <- status;
            arr_duration.(i) <- duration;
            arr_path.(i) <- path;
        | _ -> ()
      ) bl.bl_nodes;
      let columns = [
        ("name", Arrow_table.StringColumn arr_name);
        ("status", Arrow_table.StringColumn arr_status);
        ("duration", Arrow_table.FloatColumn arr_duration);
        ("path", Arrow_table.StringColumn arr_path);
      ] in
      let arrow_table = Arrow_table.create columns nrows in
      VDataFrame { arrow_table; group_keys = [] }
  | [_] -> Error.type_error "Function `build_log_to_frame` expects a BuildLog."
  | _ -> Error.arity_error_named "build_log_to_frame" 1 (List.length args)

(*
--# Gather Pipeline Node Exceptions and Warnings
--#
--# Gathers all `VError` values and warning diagnostics from computed nodes of a built pipeline
--# and returns them as a structured DataFrame.
--#
--# @name collect_exceptions
--# @param p :: Pipeline The built pipeline to gather exceptions from.
--# @return :: DataFrame A DataFrame with columns `node`, `status`, `code`, and `message`.
--# @family pipeline
--# @export
*)
let collect_exceptions_fn args _env =
  match args with
  | [VPipeline p] ->
      (match find_latest_matching_log_path p with
       | None ->
           let columns = [
             ("node", Arrow_table.StringColumn (Array.make 0 None));
             ("status", Arrow_table.StringColumn (Array.make 0 None));
             ("code", Arrow_table.StringColumn (Array.make 0 None));
             ("message", Arrow_table.StringColumn (Array.make 0 None));
           ] in
           let arrow_table = Arrow_table.create columns 0 in
           VDataFrame { arrow_table; group_keys = [] }
       | Some log_path ->
            let entries = ref [] in
            (try
               let json = Yojson.Safe.from_file log_path in
               let open Yojson.Safe.Util in
               let nodes = json |> member "nodes" |> to_list in
               List.iter (fun node_json ->
                 let name = node_json |> member "node" |> to_string in
                 let status = node_json |> member "status" |> to_string in
                 let path =
                   match node_json |> member "path" with
                   | `String s -> s
                   | _ -> ""
                 in
                 let class_val =
                   match node_json |> member "class" with
                   | `String s -> s
                   | _ -> ""
                 in
                 let has_warnings =
                   match node_json |> member "warnings" with
                   | `Bool b -> b
                   | `String s -> String.lowercase_ascii s = "true"
                   | _ -> false
                 in
                 if status = "Errored" then (
                   let err_code =
                     match node_json |> member "error_code" with
                     | `String s -> s
                     | _ -> "NixError"
                   in
                   let err_message =
                     match node_json |> member "error_message" with
                     | `String s -> s
                     | _ -> "Nix build failed."
                   in
                   let err_message_truncated = clean_and_truncate_message err_message in
                   entries := (name, "Error", err_code, err_message_truncated) :: !entries
                 ) else if status = "SoftFailed" || class_val = "VError" || class_val = "Error" then (
                   if path <> "" && Sys.file_exists path then (
                     match Serialization.read_verror_json path with
                     | Ok (VError e) ->
                         let msg_truncated = clean_and_truncate_message e.message in
                         entries := (name, "Error", Ast.Utils.error_code_to_string e.code, msg_truncated) :: !entries
                     | _ ->
                         entries := (name, "Error", class_val, "Node failed with a soft error.") :: !entries
                   ) else (
                     entries := (name, "Error", class_val, "Node failed with a soft error.") :: !entries
                   )
                 );
                 
                 (* Handle warnings *)
                 if has_warnings && path <> "" then (
                   let warnings_path = Filename.concat (Filename.dirname path) "warnings" in
                   if Sys.file_exists warnings_path then (
                     let warns = Builder_read_node.parse_node_warnings warnings_path in
                     List.iter (fun w ->
                       entries := (name, "Warning", w.nw_kind, w.nw_message) :: !entries
                     ) warns
                   )
                 )
               ) nodes
             with _ -> ());
            let entries = List.rev !entries in
           let nrows = List.length entries in
           let arr_node = Array.make nrows None in
           let arr_status = Array.make nrows None in
           let arr_code = Array.make nrows None in
           let arr_message = Array.make nrows None in
           List.iteri (fun i (node, status, code, message) ->
             arr_node.(i) <- Some node;
             arr_status.(i) <- Some status;
             arr_code.(i) <- Some code;
             arr_message.(i) <- Some message;
           ) entries;
           let columns = [
             ("node", Arrow_table.StringColumn arr_node);
             ("status", Arrow_table.StringColumn arr_status);
             ("code", Arrow_table.StringColumn arr_code);
             ("message", Arrow_table.StringColumn arr_message);
           ] in
           let arrow_table = Arrow_table.create columns nrows in
           VDataFrame { arrow_table; group_keys = [] })
  | [_] -> Error.type_error "Function `collect_exceptions` expects a Pipeline."
  | _ -> Error.arity_error_named "collect_exceptions" 1 (List.length args)

let register env =
  let env = Env.add "build_log" (make_builtin ~name:"build_log" 1 build_log_fn) env in
  let env = Env.add "build_log_to_frame" (make_builtin ~name:"build_log_to_frame" 1 build_log_to_frame_fn) env in
  let env = Env.add "collect_exceptions" (make_builtin ~name:"collect_exceptions" 1 collect_exceptions_fn) env in
  env
