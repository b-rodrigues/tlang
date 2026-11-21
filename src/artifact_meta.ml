(* src/artifact_meta.ml *)
(* Shared offline helpers for locating and reading _pipeline/ build logs and
   per-node `meta` sidecar JSON files, with mtime-based caching so callers
   (LSP hover, Schema_check, Pipeline_metrics, Provenance) share one layout
   convention and avoid repeated disk reads. *)

let max_meta_bytes = 4 * 1024 * 1024

let read_small_file ?(max_bytes=max_meta_bytes) path =
  try
    let ch = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
      let n = in_channel_length ch in
      if n > max_bytes then None
      else Some (really_input_string ch n))
  with Sys_error _ -> None

let assoc_str key pairs =
  match List.assoc_opt key pairs with
  | Some (`String s) when String.trim s <> "" -> Some (String.trim s)
  | _ -> None

let finite_float f =
  match Float.classify_float f with
  | FP_nan | FP_infinite -> None
  | _ -> Some f

let json_to_float = function
  | `Float f -> finite_float f
  | `Int i -> Some (float_of_int i)
  | `Intlit s -> (try finite_float (float_of_string s) with Failure _ -> None)
  | _ -> None

let json_to_int = function
  | `Int i -> Some i
  | `Intlit s -> (try Some (int_of_string s) with Failure _ -> None)
  | `Float f ->
      (match finite_float f with
       | Some v -> Some (int_of_float v)
       | None -> None)
  | _ -> None

let latest_build_log_in_dir pipeline_dir =
  try
    if not (Sys.file_exists pipeline_dir && Sys.is_directory pipeline_dir) then None
    else
      let entries = Array.to_list (Sys.readdir pipeline_dir) in
      let logs =
        List.filter (fun f ->
          String.starts_with ~prefix:"build_log_" f
          && String.ends_with ~suffix:".json" f
        ) entries
        |> List.sort (fun a b -> String.compare b a)
      in
      match logs with
      | latest :: _ -> Some (Filename.concat pipeline_dir latest)
      | [] -> None
  with Sys_error _ -> None

(* Cache parsed build-log node lists by (path, mtime) to avoid re-parsing on
   repeated hover or per-node schema queries. *)
let log_cache : (string, float * (string * (string * Yojson.Safe.t) list) list) Hashtbl.t =
  Hashtbl.create 8

let file_mtime path =
  try Some (Unix.stat path).Unix.st_mtime
  with Unix.Unix_error _ -> None

let parse_build_log_nodes log_path =
  match read_small_file log_path with
  | None -> []
  | Some raw ->
      (try
         match Yojson.Safe.from_string raw with
         | `Assoc pairs ->
             (match List.assoc_opt "nodes" pairs with
              | Some (`List nodes) ->
                  List.filter_map (function
                    | `Assoc entry ->
                        (match assoc_str "node" entry with
                         | Some nm -> Some (nm, entry)
                         | None -> None)
                    | _ -> None
                  ) nodes
              | _ -> [])
         | _ -> []
       with Yojson.Json_error _ -> [])

let load_build_log_nodes_cached log_path =
  match file_mtime log_path with
  | None -> []
  | Some mtime ->
      (match Hashtbl.find_opt log_cache log_path with
       | Some (cached_mtime, nodes) when cached_mtime = mtime -> nodes
       | _ ->
           let nodes = parse_build_log_nodes log_path in
           Hashtbl.replace log_cache log_path (mtime, nodes);
           nodes)

let find_node_entry_in_dir ~pipeline_dir ~node_name =
  match latest_build_log_in_dir pipeline_dir with
  | None -> None
  | Some log_path ->
      let nodes = load_build_log_nodes_cached log_path in
      List.assoc_opt node_name nodes

let meta_path_of_artifact artifact_path =
  if artifact_path = "" || artifact_path = Ast.unbuilt_path then None
  else
    try
      let p =
        if Sys.file_exists artifact_path && Sys.is_directory artifact_path then
          Filename.concat artifact_path "meta"
        else
          Filename.concat (Filename.dirname artifact_path) "meta"
      in
      if Sys.file_exists p then Some p else None
    with Sys_error _ -> None

let read_meta_json_of_artifact artifact_path : Yojson.Safe.t option =
  match meta_path_of_artifact artifact_path with
  | None -> None
  | Some mp ->
      (match read_small_file ~max_bytes:1048576 mp with
       | None -> None
       | Some raw ->
           (try Some (Yojson.Safe.from_string raw)
            with Yojson.Json_error _ -> None))

let read_meta_assoc_of_artifact artifact_path =
  match read_meta_json_of_artifact artifact_path with
  | Some (`Assoc pairs) -> Some pairs
  | _ -> None
