(* src/pipeline/builder_read_node.ml *)
open Ast
open Builder_utils
open Builder_logs

let read_node ?which_log name =
  let env_name = "T_NODE_" ^ name in
  match Sys.getenv_opt env_name with
  | Some path when which_log = None ->
      (* We are likely in a Nix sandbox. The env var points to the node's output directory.
         We look for 'artifact' and 'class' to reconstruct a partial ComputedNode. *)
      let artifact_path = Filename.concat path "artifact" in
      let class_path = Filename.concat path "class" in
      if Sys.file_exists artifact_path && Sys.file_exists class_path then
        let ch = open_in class_path in
        let cls = try input_line ch |> String.trim with _ -> "unknown" in
        close_in ch;
        
        (* Reconstruct metadata as best as we can.
           We'll mark it as 'unknown' runtime/serializer but we have the path. *)
        let cn = {
          cn_name = name;
          cn_runtime = "unknown";
          cn_path = artifact_path;
          cn_serializer = (
            match cls with 
            | "ArrowDataFrame" | "data.frame" | "DataFrame" | "Table" -> "arrow"
            | "JSON" | "VDict" | "VList" | "list" | "dict" -> "json"
            | "PMML" | "pmml" -> "pmml"
            | _ -> "default"
          );
          cn_class = cls;
          cn_dependencies = [];
        } in
        
        (* Apply auto-loading if we have a known serializer *)
        if cn.cn_serializer = "json" then
           match Serialization.read_json cn.cn_path with
           | Ok v -> v
           | Error _ -> VComputedNode cn
        else if cn.cn_serializer = "arrow" then
           match Arrow_io.read_ipc cn.cn_path with
           | Ok v -> VDataFrame { arrow_table = v; group_keys = [] }
           | Error _ -> VComputedNode cn
         else if cn.cn_serializer = "pmml" then
            match Pmml_utils.read_pmml cn.cn_path with
            | Ok v -> Pmml_utils.attach_source_path cn.cn_path v
            | Error _ -> VComputedNode cn
        else
          VComputedNode cn
      else
        Error.make_error FileError (Printf.sprintf "read_node: node `%s` found in environment as %s, but artifact is missing." name path)
  | _ ->
      let logs = match which_log with
        | Some _ -> get_all_logs ()
        | None -> get_logs ()
      in
  let log_file_result =
    match which_log with
    | None -> Ok (match logs with [] -> None | l :: _ -> Some l)
    | Some pattern ->
        (try
          Ok (List.find_opt (fun l ->
            try let _ = Str.search_forward (Str.regexp pattern) l 0 in true
            with Not_found -> false
          ) logs)
        with Failure msg ->
          Error msg)
  in
  match log_file_result with
  | Error msg ->
      Error.type_error (Printf.sprintf "read_node: invalid regex pattern for 'which_log': %s" msg)
  | Ok None ->
      let suffix = match which_log with
        | Some pat -> " matching \"" ^ pat ^ "\""
        | None -> ""
      in
      Error.make_error FileError
        (Printf.sprintf "No build logs found in `_pipeline/`%s. Run `populate_pipeline(p, build=true)` first." suffix)
  | Ok (Some f) ->
      match read_log (Filename.concat pipeline_dir f) with
      | Error msg -> Error.make_error FileError (Printf.sprintf "Failed to read log `%s`: %s" f msg)
      | Ok entries ->
          (match List.assoc_opt name entries with
          | None -> Error.make_error KeyError (Printf.sprintf "Node `%s` not found in build log `%s`." name f)
          | Some cn ->
              if cn.Ast.cn_class = "VError" then
                (match Serialization.read_json cn.Ast.cn_path with
                 | Ok v -> v
                 | Error msg -> Error.make_error ~context:[("runtime", VString cn.Ast.cn_runtime)] FileError (Printf.sprintf "Failed to read Error node `%s` from `%s`: %s" name cn.Ast.cn_path msg))
              else if cn.Ast.cn_runtime = "T"
                 && (cn.Ast.cn_serializer = "default" || cn.Ast.cn_serializer = "serialize")
              then
                (match Serialization.deserialize_from_file cn.Ast.cn_path with
                | Ok v -> v
                | Error msg -> Error.make_error ~context:[("runtime", VString cn.Ast.cn_runtime)] FileError (Printf.sprintf "Failed to read node `%s` from `%s`: %s" name cn.Ast.cn_path msg))
              else if cn.Ast.cn_serializer = "json" then
                (match Serialization.read_json cn.Ast.cn_path with
                 | Ok v -> v
                 | Error msg -> Error.make_error ~context:[("runtime", VString cn.Ast.cn_runtime)] FileError (Printf.sprintf "Failed to read JSON node `%s` from `%s`: %s" name cn.Ast.cn_path msg))
              else if cn.Ast.cn_serializer = "arrow" then
                (match Arrow_io.read_ipc cn.Ast.cn_path with
                 | Ok v -> VDataFrame { arrow_table = v; group_keys = [] }
                 | Error msg -> Error.make_error ~context:[("runtime", VString cn.Ast.cn_runtime)] FileError (Printf.sprintf "Failed to read Arrow node `%s` from `%s`: %s" name cn.Ast.cn_path msg))
              else if cn.Ast.cn_serializer = "csv" then
                (try
                  let ch = open_in cn.Ast.cn_path in
                  let content = really_input_string ch (in_channel_length ch) in
                  close_in ch;
                  T_read_csv.parse_csv_string content
                with exn ->
                  Error.make_error ~context:[("runtime", VString cn.Ast.cn_runtime)] FileError (Printf.sprintf "Failed to read CSV node `%s` from `%s`: %s" name cn.Ast.cn_path (Printexc.to_string exn)))
               else if cn.Ast.cn_serializer = "pmml" then
                 (match Pmml_utils.read_pmml cn.Ast.cn_path with
                  | Ok v -> Pmml_utils.attach_source_path cn.Ast.cn_path v
                  | Error msg -> Error.make_error ~context:[("runtime", VString cn.Ast.cn_runtime)] FileError (Printf.sprintf "Failed to read PMML node `%s` from `%s`: %s" name cn.Ast.cn_path msg))
              else
                VComputedNode cn)
