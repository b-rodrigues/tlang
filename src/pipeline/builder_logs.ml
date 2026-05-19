(* src/pipeline/builder_logs.ml *)
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

let read_log path =
  try
    let json = Yojson.Safe.from_file path in
    let open Yojson.Safe.Util in
    let nodes = json |> member "nodes" |> to_list in
    let entries = List.map (fun node_json ->
      let name = node_json |> member "node" |> to_string in
      let cn = {
        Ast.cn_name = name;
        cn_runtime = node_json |> member "runtime" |> to_string;
        cn_path = node_json |> member "path" |> to_string;
        cn_serializer = node_json |> member "serializer" |> to_string;
        cn_class = node_json |> member "class" |> to_string;
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

let parse_json_log_to_vbuildlog path =
  try
    let json = Yojson.Safe.from_file path in
    let open Yojson.Safe.Util in
    let duration =
      match json |> member "duration" with
      | `Float f -> f
      | `Int i -> float_of_int i
      | `String s -> (try float_of_string s with _ -> 0.0)
      | _ -> 0.0
    in
    let nodes_list = json |> member "nodes" |> to_list in
    let parse_node node_json =
      let name = node_json |> member "node" |> to_string in
      let success =
        match node_json |> member "success" with
        | `Bool b -> b
        | `String s -> s = "true"
        | _ -> true
      in
      let status =
        if success then "Completed" else "SoftFailed"
      in
      let node_duration =
        match node_json |> member "duration" with
        | `Float f -> f
        | `Int i -> float_of_int i
        | `String s -> (try float_of_string s with _ -> 0.0)
        | _ -> 0.0
      in
      let record_fields = [
        ("name", Ast.VString name);
        ("status", Ast.VString status);
        ("duration", Ast.VFloat node_duration);
      ] in
      (Ast.VDict record_fields, name, success)
    in
    let parsed_nodes = List.map parse_node nodes_list in
    let bl_nodes = List.map (fun (v, _, _) -> v) parsed_nodes in
    let bl_failed_nodes =
      parsed_nodes
      |> List.filter (fun (_, _, success) -> not success)
      |> List.map (fun (_, name, _) -> name)
    in
    Ast.VBuildLog { bl_nodes; bl_duration = duration; bl_failed_nodes }
  with _exn ->
    Ast.VBuildLog { bl_nodes = []; bl_duration = 0.0; bl_failed_nodes = [] }
