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
  try
    let (ch_in, _ch_out, ch_err as proc) = Unix.open_process_full cmd (Unix.environment ()) in
    close_out _ch_out;
    let fd_in = Unix.descr_of_in_channel ch_in in
    let fd_err = Unix.descr_of_in_channel ch_err in
    let buf = Bytes.create 1024 in
    (* Separate line-assembly buffers per FD to avoid merging partial lines
       from different streams. *)
    let line_buf_in = Buffer.create 256 in
    let line_buf_err = Buffer.create 256 in

    let process_bytes_to line_buf n =
      for i = 0 to n - 1 do
        let c = Bytes.get buf i in
        if c = '\n' || c = '\r' then (
          let line = Buffer.contents line_buf in
          if line <> "" then callback line;
          Buffer.clear line_buf
        ) else Buffer.add_char line_buf c
      done
    in

    let rec drain in_open err_open =
      if not in_open && not err_open then ()
      else
        let read_fds =
          [] |> (fun acc -> if in_open then fd_in :: acc else acc)
             |> (fun acc -> if err_open then fd_err :: acc else acc)
        in
        let ready, _, _ = Unix.select read_fds [] [] (-1.) in

        let in_open =
          if in_open && List.mem fd_in ready then (
            let n = try Unix.read fd_in buf 0 1024 with _ -> 0 in
            if n = 0 then false else (process_bytes_to line_buf_in n; true)
          ) else in_open
        in

        let err_open =
          if err_open && List.mem fd_err ready then (
            let n = try Unix.read fd_err buf 0 1024 with _ -> 0 in
            if n = 0 then false else (process_bytes_to line_buf_err n; true)
          ) else err_open
        in

        drain in_open err_open
    in

    (* Use a flag to avoid double-closing if close_process_full succeeds
       normally but Fun.protect's finally would close again. *)
    let cleanup_done = ref false in
    let status =
      Fun.protect
        ~finally:(fun () ->
          if not !cleanup_done then
            (try ignore (Unix.close_process_full proc) with _ -> ()))
        (fun () ->
          drain true true;
          (* Flush any unterminated final lines from each stream. *)
          let flush_buf b =
            let line = Buffer.contents b in
            if line <> "" then callback line
          in
          flush_buf line_buf_in;
          flush_buf line_buf_err;
          let s = Unix.close_process_full proc in
          cleanup_done := true;
          s)
    in
    Ok status
  with exn ->
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
