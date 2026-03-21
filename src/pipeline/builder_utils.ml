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

let read_file_first_line path =
  try
    let ic = open_in path in
    let line = try input_line ic with End_of_file -> "" in
    close_in ic;
    Some (String.trim line)
  with _ -> None

let command_exists cmd =
  Sys.command (Printf.sprintf "command -v %s >/dev/null 2>&1" cmd) = 0

let run_command_stream cmd callback =
  (* All callers redirect stderr to stdout via 2>&1, so open_process_in suffices
     and avoids a dangling unread stderr pipe that could block the child process. *)
  let ch = Unix.open_process_in cmd in
  try
    let rec loop () =
      match input_line ch with
      | line ->
          callback line;
          loop ()
      | exception End_of_file -> ()
    in
    loop ();
    Ok (Unix.close_process_in ch)
  with exn ->
    (* Ensure the process is reaped even when callback or I/O raises. *)
    (try ignore (Unix.close_process_in ch) with _ -> ());
    Error (Printexc.to_string exn)

let run_command_capture cmd =
  let b = Buffer.create 256 in
  match run_command_stream cmd (fun line -> Buffer.add_string b line; Buffer.add_char b '\n') with
  | Ok status -> Ok (status, String.trim (Buffer.contents b))
  | Error msg -> Error msg

let ensure_pipeline_dir () =
  if not (Sys.file_exists pipeline_dir) then
    Unix.mkdir pipeline_dir 0o755

let rec find_project_root dir =
  if Sys.file_exists (Filename.concat dir "flake.nix") || Sys.file_exists (Filename.concat dir "dune-project") then
    dir
  else
    let parent = Filename.dirname dir in
    if parent = dir then dir (* Reached filesystem root *)
    else find_project_root parent

let get_project_root () =
  find_project_root (Sys.getcwd ())

let get_relative_path_to_root () =
  let cwd = Sys.getcwd () in
  let root = find_project_root cwd in
  let rec count_levels dir root acc =
    if dir = root then acc
    else 
      let parent = Filename.dirname dir in
      if parent = dir then acc (* Should not happen if root was found *)
      else count_levels parent root (acc + 1)
  in
  let levels = count_levels cwd root 1 in
  String.concat "/" (List.init levels (fun _ -> ".."))

let get_timestamp () =
  let tm = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d%02d%02d_%02d%02d%02d"
    (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_min tm.tm_sec
