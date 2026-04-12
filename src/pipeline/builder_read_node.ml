(* src/pipeline/builder_read_node.ml *)
open Ast
open Builder_utils
open Builder_logs

let parse_node_warnings path =
  if Sys.file_exists path then
    match Serialization.read_json path with
    | Ok (VList items) ->
        List.filter_map (fun (_, v) ->
          match v with
          | VString msg ->
              Some {
                nw_kind = "Generic";
                nw_fn = "unknown";
                nw_na_count = 0;
                nw_na_indices = [];
                nw_message = msg;
                nw_source = WarningOwn;
              }
          | VDict d ->
              let get_s k = match List.assoc_opt k d with Some (VString s) -> s | _ -> "" in
              let get_i k = match List.assoc_opt k d with Some (VInt i) -> i | _ -> 0 in
              Some {
                nw_kind = get_s "kind" |> (fun s -> if s = "" then "Generic" else s);
                nw_fn = get_s "fn" |> (fun s -> if s = "" then "unknown" else s);
                nw_na_count = get_i "na_count";
                nw_na_indices = (match List.assoc_opt "na_indices" d with Some (VList l) -> List.filter_map (fun (_, v) -> match v with VInt i -> Some i | _ -> None) l | _ -> []);
                nw_message = get_s "message";
                nw_source = WarningOwn;
              }
          | _ -> None
        ) items
    | _ -> []
  else []

let wrap_with_diagnostics name cn v =
  let node_dir = Filename.dirname cn.cn_path in
  let warnings_path = Filename.concat node_dir "warnings" in
  let warnings = parse_node_warnings warnings_path in
  let error = if cn.cn_class = "VError" then (
    match v with
    | VError e -> Some { ne_kind = Utils.error_code_to_string e.code; ne_fn = "unknown"; ne_message = e.message; ne_na_count = e.na_count }
    | _ -> None
  ) else None in
  VNodeResult { v; node_name = name; diagnostics = { nd_warnings = warnings; nd_error = error } }

let read_node ?which_log name =
  let env_name = "T_NODE_" ^ name in
  match Sys.getenv_opt env_name with
  | Some path when which_log = None ->
      let artifact_path = Filename.concat path "artifact" in
      let class_path = Filename.concat path "class" in
      if Sys.file_exists artifact_path && Sys.file_exists class_path then
        let ch = open_in class_path in
        let cls = try input_line ch |> String.trim with _ -> "unknown" in
        close_in ch;
        
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
        
        let v = 
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
        in
        wrap_with_diagnostics name cn v
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
              let v =
                if cn.Ast.cn_class = "VError" then
                  (match Serialization.read_verror_json cn.Ast.cn_path with
                   | Ok (VError e) ->
                       VError { e with context = ("node_name", VString name) :: e.context }
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
                  VComputedNode cn
              in
              wrap_with_diagnostics name cn v)
