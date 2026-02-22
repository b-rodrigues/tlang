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
    let ic = open_in path in
    let len = in_channel_length ic in
    let raw = really_input_string ic len in
    close_in ic;
    let re_node = Str.regexp "\"node\": \"\\([^\"]+\\)\"" in
    let re_path = Str.regexp "\"path\": \"\\([^\"]+\\)\"" in
    let rec collect pos acc =
      try
        let _ = Str.search_forward re_node raw pos in
        let node = Str.matched_group 1 raw in
        let next_pos = Str.match_end () in
        let _ = Str.search_forward re_path raw next_pos in
        let path = Str.matched_group 1 raw in
        collect (Str.match_end ()) ((node, path) :: acc)
      with Not_found -> List.rev acc
    in
    Ok (collect 0 [])
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
