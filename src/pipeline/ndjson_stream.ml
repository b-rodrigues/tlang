(* src/pipeline/ndjson_stream.ml *)
(* Streaming NDJSON events for `t run --json`.
   One JSON object per line on stdout, consumed by agents and LLMs. *)

open Builder_utils

let schema_version = "1.0"

(* --- Mutable state --- *)

let seq_counter = ref 0
let run_start_time = ref 0.0

let reset () =
  seq_counter := 0;
  run_start_time := 0.0

let next_seq () =
  incr seq_counter;
  !seq_counter

(* --- Helpers --- *)

let iso8601_timestamp () =
  let tm = Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec
    0

let emit_json json =
  let line = Yojson.Safe.to_string json in
  Printf.printf "%s\n%!" line

let truncate_tail ~max_lines s =
  let lines = String.split_on_char '\n' s in
  let len = List.length lines in
  if len <= max_lines then s
  else
    let kept = List.filteri (fun i _ -> i >= len - max_lines) lines in
    String.concat "\n" kept

let build_logs_dir = Filename.concat pipeline_dir "logs"

let ensure_build_logs_dir () =
  if not (Sys.file_exists build_logs_dir) then
    (try Unix.mkdir build_logs_dir 0o755
     with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  build_logs_dir

let log_path_for_node node_id =
  Filename.concat build_logs_dir (node_id ^ ".log")

(* --- Node metadata extraction --- *)

type node_spec = {
  ns_id : string;
  ns_lang : string;
  ns_deps : string list;
}

(* --- Event emitters --- *)

let emit_run_started ?pipeline_name ~(nodes : node_spec list) () =
  let seq = next_seq () in
  let nodes_json =
    List.map (fun (n : node_spec) ->
      `Assoc [
        ("id", `String n.ns_id);
        ("lang", `String n.ns_lang);
        ("depends_on", `List (List.map (fun d -> `String d) n.ns_deps));
      ]
    ) nodes
  in
  let base = [
    ("seq", `Int seq);
    ("ts", `String (iso8601_timestamp ()));
    ("event", `String "run_started");
    ("schema_version", `String schema_version);
    ("nodes", `List nodes_json);
  ] in
  let with_project = match pipeline_name with
    | Some name -> base @ [("project", `String name)]
    | None -> base
  in
  emit_json (`Assoc with_project)

let emit_node_failed ~node_id ~lang ~duration_ms ~error_class ~message
    ~log_available ~log_path ~log_tail =
  let seq = next_seq () in
  let log_json = `Assoc [
    ("available", `Bool log_available);
    ("path", `String log_path);
    ("tail", `String log_tail);
  ] in
  let error_json = `Assoc [
    ("error_class", `String error_class);
    ("message", `String message);
  ] in
  emit_json (`Assoc [
    ("seq", `Int seq);
    ("ts", `String (iso8601_timestamp ()));
    ("event", `String "node_failed");
    ("node", `Assoc [
      ("id", `String node_id);
      ("lang", `String lang);
    ]);
    ("duration_ms", `Int (int_of_float duration_ms));
    ("error", error_json);
    ("log", log_json);
  ])

let emit_node_skipped ~node_id ~caused_by =
  let seq = next_seq () in
  emit_json (`Assoc [
    ("seq", `Int seq);
    ("ts", `String (iso8601_timestamp ()));
    ("event", `String "node_skipped");
    ("node", `Assoc [
      ("id", `String node_id);
    ]);
    ("caused_by", `List (List.map (fun s -> `String s) caused_by));
  ])

let emit_run_finished ~status ~total ~succeeded ~cached ~failed
    ~skipped_upstream ~root_causes =
  let seq = next_seq () in
  emit_json (`Assoc [
    ("seq", `Int seq);
    ("ts", `String (iso8601_timestamp ()));
    ("event", `String "run_finished");
    ("status", `String status);
    ("summary", `Assoc [
      ("total", `Int total);
      ("succeeded", `Int succeeded);
      ("cached", `Int cached);
      ("failed", `Int failed);
      ("skipped_upstream", `Int skipped_upstream);
    ]);
    ("root_causes", `List (List.map (fun s -> `String s) root_causes));
  ])
