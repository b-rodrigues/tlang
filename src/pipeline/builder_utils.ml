(* src/pipeline/builder_utils.ml *)

let pipeline_dir = "_pipeline"
let pipeline_nix_path = Filename.concat pipeline_dir "pipeline.nix"
let dag_path = Filename.concat pipeline_dir "dag.json"
let env_nix_path = Filename.concat pipeline_dir "env.nix"

let write_file path content =
  try
    let oc = open_out path in
    output_string oc content;
    close_out oc;
    Ok ()
  with exn ->
    Error (Printexc.to_string exn)

let command_exists cmd =
  Sys.command (Printf.sprintf "command -v %s >/dev/null 2>&1" cmd) = 0

let run_command_capture cmd =
  try
    let ic = Unix.open_process_in cmd in
    let b = Buffer.create 256 in
    (try
       while true do
         Buffer.add_string b (input_line ic);
         Buffer.add_char b '\n'
       done
     with End_of_file -> ());
    let status = Unix.close_process_in ic in
    Ok (status, String.trim (Buffer.contents b))
  with exn ->
    Error (Printexc.to_string exn)

let ensure_pipeline_dir () =
  if not (Sys.file_exists pipeline_dir) then
    Unix.mkdir pipeline_dir 0o755

let get_timestamp () =
  let tm = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d%02d%02d_%02d%02d%02d"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec
