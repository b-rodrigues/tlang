(* src/pipeline/builder_logs.ml *)
open Builder_utils

let get_logs () =
  if not (Sys.file_exists pipeline_dir) then []
  else
    Sys.readdir pipeline_dir
    |> Array.to_list
    |> List.filter (fun f ->
      Filename.check_suffix f ".json"
      && String.starts_with ~prefix:"build_log_" f)
    |> List.sort (fun a b -> compare b a)

let read_log path =
  try
    let json = Yojson.Safe.from_file path in
    let open Yojson.Safe.Util in
    let _timestamp = json |> member "timestamp" |> to_string in
    let _hash = json |> member "hash" |> to_string in
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
