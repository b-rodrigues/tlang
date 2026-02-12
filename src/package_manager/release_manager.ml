(* src/package_manager/release_manager.ml *)
(* Handles release validation and git tagging for t publish *)

open Package_types

(** Execute a shell command and return Ok stdout or Error stderr/exit_code *)
let run_command cmd : (string, string) result =
  try
    let (ch_in, ch_out, ch_err) = Unix.open_process_full cmd (Unix.environment ()) in
    close_out ch_out; (* Close stdin to the process *)

    let out_buf = Buffer.create 1024 in
    let err_buf = Buffer.create 1024 in
    let buf = Bytes.create 4096 in

    (* Drain stdout and stderr concurrently to avoid deadlock on full pipe buffers. *)
    let fd_out = Unix.descr_of_in_channel ch_in in
    let fd_err = Unix.descr_of_in_channel ch_err in

    let rec drain out_open err_open =
      if not out_open && not err_open then
        ()
      else
        let read_fds =
          [] |> (fun acc -> if out_open then fd_out :: acc else acc)
             |> (fun acc -> if err_open then fd_err :: acc else acc)
        in
        let ready, _, _ = Unix.select read_fds [] [] (-1.) in
        let out_open =
          if out_open && List.mem fd_out ready then (
            let n = input ch_in buf 0 (Bytes.length buf) in
            if n = 0 then
              false
            else (
              Buffer.add_subbytes out_buf buf 0 n;
              true
            )
          ) else out_open
        in
        let err_open =
          if err_open && List.mem fd_err ready then (
            let n = input ch_err buf 0 (Bytes.length buf) in
            if n = 0 then
              false
            else (
              Buffer.add_subbytes err_buf buf 0 n;
              true
            )
          ) else err_open
        in
        drain out_open err_open
    in
    drain true true;

    let status = Unix.close_process_full (ch_in, ch_out, ch_err) in
    match status with
    | Unix.WEXITED 0 -> Ok (String.trim (Buffer.contents out_buf))
    | Unix.WEXITED n -> 
        let err_msg = String.trim (Buffer.contents err_buf) in
        if err_msg <> "" then Error (Printf.sprintf "Command '%s' failed (exit %d): %s" cmd n err_msg)
        else Error (Printf.sprintf "Command '%s' failed with exit code %d" cmd n)
    | _ -> Error (Printf.sprintf "Command '%s' failed unexpectedly" cmd)
  with e -> Error (Printexc.to_string e)

(** Check if git working directory is clean *)
let validate_clean_git () =
  match run_command "git status --porcelain" with
  | Ok output ->
      if String.trim output = "" then Ok ()
      else Error "Git working directory is not clean. Commit or stash changes first."
  | Error msg -> Error ("Failed to check git status: " ^ msg)

(** Run the test suite *)
let validate_tests_pass () =
  Printf.printf "Running tests...\n";
  match Sys.command "dune test" with
  | 0 -> Ok ()
  | n -> Error (Printf.sprintf "Tests failed (exit code %d). Fix tests before publishing." n)

(** Parse version from DESCRIPTION.toml *)
let get_package_version dir =
  let desc_path = Filename.concat dir "DESCRIPTION.toml" in
  if not (Sys.file_exists desc_path) then
    Error "DESCRIPTION.toml not found"
  else
    let ch = open_in desc_path in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    match Toml_parser.parse_description_toml content with
    | Ok config -> Ok config.version
    | Error msg -> Error ("Failed to parse DESCRIPTION.toml: " ^ msg)

(** Check if CHANGELOG.md contains an entry for the given version *)
let validate_changelog dir version =
  let changelog_path = Filename.concat dir "CHANGELOG.md" in
  if not (Sys.file_exists changelog_path) then
    Error "CHANGELOG.md not found"
  else
    let ch = open_in changelog_path in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    (* Look for "## [version]" or "## version" *)
    let pattern = Str.regexp_string version in
    try
      ignore (Str.search_forward pattern content 0);
      Ok ()
    with Not_found ->
      Error (Printf.sprintf "CHANGELOG.md does not contain an entry for version %s" version)

(** Create a git tag *)
let create_git_tag version =
  let tag = "v" ^ version in
  let msg = Printf.sprintf "Release %s" tag in
  let cmd = Printf.sprintf "git tag -a %s -m \"%s\"" tag msg in
  match run_command cmd with
  | Ok _ -> Ok tag
  | Error e -> Error ("Failed to create git tag: " ^ e)

(** Push a git tag *)
let push_git_tag tag =
  let cmd = Printf.sprintf "git push origin %s" tag in
  match run_command cmd with
  | Ok _ -> Ok ()
  | Error e -> Error ("Failed to push git tag: " ^ e)
