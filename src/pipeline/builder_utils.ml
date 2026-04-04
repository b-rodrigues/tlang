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
        let rec do_select () =
          try Unix.select read_fds [] [] (-1.)
          with Unix.Unix_error (Unix.EINTR, _, _) -> do_select ()
        in
        let ready, _, _ = do_select () in

        let in_open =
          if in_open && List.mem fd_in ready then (
            let rec do_read () =
              try Unix.read fd_in buf 0 1024
              with Unix.Unix_error (Unix.EINTR, _, _) -> do_read ()
                 | Unix.Unix_error _ as exn -> raise exn
            in
            let n = do_read () in
            if n = 0 then false else (process_bytes_to line_buf_in n; true)
          ) else in_open
        in

        let err_open =
          if err_open && List.mem fd_err ready then (
            let rec do_read () =
              try Unix.read fd_err buf 0 1024
              with Unix.Unix_error (Unix.EINTR, _, _) -> do_read ()
                 | Unix.Unix_error _ as exn -> raise exn
            in
            let n = do_read () in
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

(** Like [run_command_stream] but takes an explicit argument vector,
    bypassing shell interpretation. Use for commands with user-supplied
    arguments (file paths, derivation paths, etc.). *)
let run_command_stream_argv (argv : string array) callback =
  if Array.length argv = 0 then Error "run_command_stream_argv: empty argument vector"
  else
  try
    let prog = argv.(0) in
    let (ch_in, _ch_out, ch_err as proc) =
      Unix.open_process_args_full prog argv (Unix.environment ())
    in
    close_out _ch_out;
    let fd_in = Unix.descr_of_in_channel ch_in in
    let fd_err = Unix.descr_of_in_channel ch_err in
    let buf = Bytes.create 1024 in
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
        let rec do_select () =
          try Unix.select read_fds [] [] (-1.)
          with Unix.Unix_error (Unix.EINTR, _, _) -> do_select ()
        in
        let ready, _, _ = do_select () in

        let in_open =
          if in_open && List.mem fd_in ready then (
            let rec do_read () =
              try Unix.read fd_in buf 0 1024
              with Unix.Unix_error (Unix.EINTR, _, _) -> do_read ()
                 | Unix.Unix_error _ as exn -> raise exn
            in
            let n = do_read () in
            if n = 0 then false else (process_bytes_to line_buf_in n; true)
          ) else in_open
        in

        let err_open =
          if err_open && List.mem fd_err ready then (
            let rec do_read () =
              try Unix.read fd_err buf 0 1024
              with Unix.Unix_error (Unix.EINTR, _, _) -> do_read ()
                 | Unix.Unix_error _ as exn -> raise exn
            in
            let n = do_read () in
            if n = 0 then false else (process_bytes_to line_buf_err n; true)
          ) else err_open
        in

        drain in_open err_open
    in

    let cleanup_done = ref false in
    let status =
      Fun.protect
        ~finally:(fun () ->
          if not !cleanup_done then
            (try ignore (Unix.close_process_full proc) with _ -> ()))
        (fun () ->
          drain true true;
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

(** Execute a command with an explicit argument vector, bypassing shell interpretation.
    This prevents shell injection when arguments contain user-supplied data
    (e.g. file paths, derivation paths). *)
let run_command_argv_exit (argv : string array) : (int, string) result =
  if Array.length argv = 0 then Error "run_command_argv_exit: empty argument vector"
  else
    try
      let prog = argv.(0) in
      let (ch_in, ch_out, ch_err) =
        Unix.open_process_args_full prog argv (Unix.environment ())
      in
      close_out ch_out;
      (* Drain both channels to avoid deadlock *)
      let buf = Bytes.create 4096 in
      let drain_channel ch =
        try while true do
          let n = input ch buf 0 (Bytes.length buf) in
          if n = 0 then raise Exit
        done with _ -> ()
      in
      drain_channel ch_in;
      drain_channel ch_err;
      let status = Unix.close_process_full (ch_in, ch_out, ch_err) in
      (match status with
       | Unix.WEXITED n -> Ok n
       | Unix.WSIGNALED n -> Ok (-(abs n))
       | Unix.WSTOPPED n -> Ok (-(abs n)))
    with e -> Error (Printexc.to_string e)

(** Execute a command with an explicit argument vector and capture stdout. *)
let run_command_argv_capture (argv : string array) : (string, string) result =
  if Array.length argv = 0 then Error "run_command_argv_capture: empty argument vector"
  else
    try
      let prog = argv.(0) in
      let (ch_in, ch_out, ch_err) =
        Unix.open_process_args_full prog argv (Unix.environment ())
      in
      close_out ch_out;
      let out_buf = Buffer.create 1024 in
      let err_buf = Buffer.create 1024 in
      let buf = Bytes.create 4096 in
      let fd_out = Unix.descr_of_in_channel ch_in in
      let fd_err = Unix.descr_of_in_channel ch_err in
      let rec drain out_open err_open =
        if not out_open && not err_open then ()
        else
          let read_fds =
            [] |> (fun acc -> if out_open then fd_out :: acc else acc)
               |> (fun acc -> if err_open then fd_err :: acc else acc)
          in
          let rec do_select () =
            try Unix.select read_fds [] [] (-1.)
            with Unix.Unix_error (Unix.EINTR, _, _) -> do_select ()
          in
          let ready, _, _ = do_select () in
          let out_open =
            if out_open && List.mem fd_out ready then (
              let n = input ch_in buf 0 (Bytes.length buf) in
              if n = 0 then false
              else (Buffer.add_subbytes out_buf buf 0 n; true)
            ) else out_open
          in
          let err_open =
            if err_open && List.mem fd_err ready then (
              let n = input ch_err buf 0 (Bytes.length buf) in
              if n = 0 then false
              else (Buffer.add_subbytes err_buf buf 0 n; true)
            ) else err_open
          in
          drain out_open err_open
      in
      drain true true;
      let cmd_display = String.concat " " (Array.to_list argv) in
      let status = Unix.close_process_full (ch_in, ch_out, ch_err) in
      (match status with
       | Unix.WEXITED 0 -> Ok (String.trim (Buffer.contents out_buf))
       | Unix.WEXITED n ->
           let err_msg = String.trim (Buffer.contents err_buf) in
           if err_msg <> "" then
             Error (Printf.sprintf "Command '%s' failed (exit %d): %s" cmd_display n err_msg)
           else
             Error (Printf.sprintf "Command '%s' failed with exit code %d" cmd_display n)
       | _ -> Error (Printf.sprintf "Command '%s' failed unexpectedly" cmd_display))
    with e -> Error (Printexc.to_string e)

let ensure_pipeline_dir () =
  if not (Sys.file_exists pipeline_dir) then
    Unix.mkdir pipeline_dir 0o755

let rec find_project_root dir =
  if Sys.file_exists (Filename.concat dir "flake.nix") || Sys.file_exists (Filename.concat dir "dune-project") || Sys.file_exists (Filename.concat dir "tproject.toml") then
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
