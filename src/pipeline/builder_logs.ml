(* src/pipeline/builder_logs.ml *)
open Ast
open Builder_utils

let get_all_logs () =
  if not (Sys.file_exists pipeline_dir) then []
  else
    let logs =
      Sys.readdir pipeline_dir
      |> Array.to_list
      |> List.filter (fun f ->
        Filename.check_suffix f ".json"
        && String.starts_with ~prefix:"build_log_" f)
    in
    let logs_with_mtime =
      List.map (fun f ->
        let path = Filename.concat pipeline_dir f in
        let stats = Unix.stat path in
        (f, stats.Unix.st_mtime)
      ) logs
    in
    logs_with_mtime
    |> List.sort (fun (_, t1) (_, t2) -> compare t2 t1)
    |> List.map fst

let get_logs () =
  if not (Sys.file_exists pipeline_dir) then []
  else
    let logs = get_all_logs () in
    let logs =
      if List.length logs > 1 && List.exists (fun f -> f <> "build_log_ocaml_mock.json" && f <> "build_log_legacy_version.json") logs then
        List.filter (fun f ->
          f <> "build_log_ocaml_mock.json"
          && f <> "build_log_legacy_version.json"
        ) logs
      else logs
    in
    logs

let find_log_for_out_path out_path =
  if out_path = "" then None
  else
    let logs = get_logs () in
    let matches_out_path log_file =
      let path = Filename.concat pipeline_dir log_file in
      try
        let json = Yojson.Safe.from_file path in
        let open Yojson.Safe.Util in
        match json |> member "out_path" with
        | `String logged_out_path -> logged_out_path = out_path
        | _ -> false
      with _ ->
        false
    in
    match List.find_opt matches_out_path logs with
    | Some log_file -> Some (Filename.concat pipeline_dir log_file)
    | None -> None

let read_log path =
  try
    let json = Yojson.Safe.from_file path in
    let open Yojson.Safe.Util in
    let nodes = json |> member "nodes" |> to_list in
    let entries = List.map (fun node_json ->
      let name = node_json |> member "node" |> to_string in
      let status =
        match node_json |> member "status" with
        | `String s -> s
        | _ -> ""
      in
      let err_code =
        match node_json |> member "error_code" with
        | `String s -> s
        | _ -> ""
      in
      let cn_class =
        if status = "Errored" || status = "SoftFailed" then
          (if err_code <> "" then err_code else "Error")
        else
          node_json |> member "class" |> to_string
      in
      let cn_path =
        if status = "Errored" then ""
        else node_json |> member "path" |> to_string
      in
      let cn = {
        Ast.cn_name = name;
        cn_runtime = node_json |> member "runtime" |> to_string;
        cn_path;
        cn_serializer = node_json |> member "serializer" |> to_string;
        cn_class;
        cn_dependencies = node_json |> member "dependencies" |> to_list |> filter_string;
      } in
      (name, cn)
    ) nodes in
    Ok entries
  with exn -> Error (Printexc.to_string exn)

let list_logs () =
  let logs = get_logs () in
  let nrows = List.length logs in
  let arr_filename = Array.init nrows (fun i -> Some (List.nth logs i)) in
  let arr_mtime = Array.init nrows (fun i ->
    let f = List.nth logs i in
    let path = Filename.concat pipeline_dir f in
    let stats = Unix.stat path in
    let tm = Unix.localtime stats.Unix.st_mtime in
    Some (Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d"
      (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec)
  ) in
  let arr_size = Array.init nrows (fun i ->
    let f = List.nth logs i in
    let path = Filename.concat pipeline_dir f in
    let stats = Unix.stat path in
    let raw_kb = float_of_int stats.Unix.st_size /. 1024.0 in
    let size_kb = Float.round (raw_kb *. 100.0) /. 100.0 in
    Some size_kb
  ) in
  let columns = [
    ("filename", Arrow_table.StringColumn arr_filename);
    ("modification_time", Arrow_table.StringColumn arr_mtime);
    ("size_kb", Arrow_table.FloatColumn arr_size);
  ] in
  let arrow_table = Arrow_table.create columns nrows in
  Ast.VDataFrame { arrow_table; group_keys = [] }

let parse_json_log_to_vbuildlog log_path =
  let open Yojson.Safe.Util in
  let parse_float_or_default = function
    | `Float f -> f
    | `Int i -> float_of_int i
    | `String s -> (try float_of_string s with _ -> 0.0)
    | _ -> 0.0
  in
  let parse_success_with_default node_json default =
    match node_json |> member "success" with
    | `Bool b -> b
    | `String s -> String.lowercase_ascii s = "true"
    | _ -> default
  in
  try
    if not (Sys.file_exists log_path) then
      Error.make_error FileError (Printf.sprintf "Build log `%s` does not exist." log_path)
    else
      let json = Yojson.Safe.from_file log_path in
      let duration = parse_float_or_default (json |> member "duration") in
      let out_path =
        match json |> member "out_path" with
        | `String p -> Some p
        | _ -> None
      in
      let nodes_list = json |> member "nodes" |> to_list in
      let parse_node node_json =
        let name = node_json |> member "node" |> to_string in
        let node_path =
          match node_json |> member "path" with
          | `String s -> s
          | _ -> ""
        in
        let status_from_json =
          match node_json |> member "status" with
          | `String s when s <> "" -> Some s
          | _ -> None
        in
        let status =
          match status_from_json with
          | Some s -> s
          | None ->
              let success = parse_success_with_default node_json true in
              if success then "Completed" else "SoftFailed"
        in
        let success_default = String.equal status "Completed" in
        let success = parse_success_with_default node_json success_default in
        let node_duration = parse_float_or_default (node_json |> member "duration") in
        let has_warnings =
          match node_json |> member "warnings" with
          | `Bool b -> b
          | `String s -> String.lowercase_ascii s = "true"
          | _ -> false
        in
        let display_status =
          if status = "SoftFailed" then "Completed with error"
          else if status = "Completed" && has_warnings then "Completed with warning"
          else status
        in
        let is_failed =
          match String.lowercase_ascii status with
          | "completed" -> false
          | "softfailed" | "errored" -> true
          | _ -> not success
        in
        let record_fields = [
          ("name", Ast.VString name);
          ("status", Ast.VString display_status);
          ("duration", Ast.VFloat node_duration);
          ("path", Ast.VString node_path);
        ] in
        (Ast.VDict record_fields, name, is_failed)
      in
      let parsed_nodes = List.map parse_node nodes_list in
      let bl_nodes = List.map (fun (v, _, _) -> v) parsed_nodes in
      let bl_failed_nodes =
        parsed_nodes
        |> List.filter (fun (_, _, is_failed) -> is_failed)
        |> List.map (fun (_, name, _) -> name)
      in
      Ast.VBuildLog { bl_nodes; bl_duration = duration; bl_failed_nodes; bl_out_path = out_path }
  with
  | Sys_error msg ->
      Error.make_error FileError (Printf.sprintf "Failed to read build log `%s`: %s" log_path msg)
  | Yojson.Json_error msg ->
      Error.make_error ValueError (Printf.sprintf "Malformed JSON in build log `%s`: %s" log_path msg)
  | Yojson.Safe.Util.Type_error (msg, _) ->
      Error.make_error StructuralError (Printf.sprintf "Invalid build log structure in `%s`: %s" log_path msg)
  | Failure msg ->
      Error.make_error StructuralError (Printf.sprintf "Invalid build log `%s`: %s" log_path msg)
  | exn ->
      Error.make_error RuntimeError
        (Printf.sprintf "Unexpected error while parsing build log `%s`: %s" log_path (Printexc.to_string exn))
