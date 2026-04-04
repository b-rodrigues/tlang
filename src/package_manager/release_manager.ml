(* src/package_manager/release_manager.ml *)
(* Handles release validation and git tagging for t publish *)

open Package_types

(** Execute a shell command and return Ok stdout or Error stderr/exit_code.
    SECURITY NOTE: Only use this for fixed, trusted command strings.
    For commands that include user-supplied data, use [run_command_argv] instead. *)
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

(** Execute a command with an explicit argument vector, bypassing shell interpretation.
    This prevents shell injection when arguments contain user-supplied data. *)
let run_command_argv (argv : string array) : (string, string) result =
  if Array.length argv = 0 then Error "run_command_argv: empty argument vector"
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
          let ready, _, _ = Unix.select read_fds [] [] (-1.) in
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
      match status with
      | Unix.WEXITED 0 -> Ok (String.trim (Buffer.contents out_buf))
      | Unix.WEXITED n ->
          let err_msg = String.trim (Buffer.contents err_buf) in
          if err_msg <> "" then
            Error (Printf.sprintf "Command '%s' failed (exit %d): %s" cmd_display n err_msg)
          else
            Error (Printf.sprintf "Command '%s' failed with exit code %d" cmd_display n)
      | _ -> Error (Printf.sprintf "Command '%s' failed unexpectedly" cmd_display)
    with e -> Error (Printexc.to_string e)

(** Validate that a version string contains only safe characters.
    Accepts semver-like versions: digits, dots, hyphens, and alphanumerics. *)
let validate_version_format version =
  let is_safe c =
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || c = '.' || c = '-' || c = '_'
  in
  if String.length version = 0 then
    Error "Version string is empty."
  else if String.for_all is_safe version then
    Ok ()
  else
    Error (Printf.sprintf "Version `%s` contains invalid characters. Only alphanumerics, dots, hyphens, and underscores are allowed."
             (String.sub version 0 (min 40 (String.length version))))

(** Check if git working directory is clean *)
let validate_clean_git () =
  match run_command "git status --porcelain" with
  | Ok output ->
      if String.trim output = "" then Ok ()
      else Error "Git working directory is not clean. Commit or stash changes first."
  | Error msg -> Error ("Failed to check git status: " ^ msg)

(** Check if the current git repository has at least one configured remote *)
let validate_git_remote () =
  match run_command "git remote" with
  | Ok output ->
      if String.trim output = "" then
        Error "Git remote is not configured. Add a remote and push the project before running `t update`."
      else
        Ok ()
  | Error msg -> Error ("Failed to check git remotes: " ^ msg)

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

(** Create a git tag — uses argv-based execution to prevent shell injection *)
let create_git_tag version =
  match validate_version_format version with
  | Error msg -> Error ("Invalid version for git tag: " ^ msg)
  | Ok () ->
      let tag = "v" ^ version in
      let msg = Printf.sprintf "Release %s" tag in
      let argv = [| "git"; "tag"; "-a"; tag; "-m"; msg |] in
      match run_command_argv argv with
      | Ok _ -> Ok tag
      | Error e -> Error ("Failed to create git tag: " ^ e)

(** Push a git tag — uses argv-based execution to prevent shell injection *)
let push_git_tag tag =
  match validate_version_format tag with
  | Error msg -> Error ("Invalid tag for git push: " ^ msg)
  | Ok () ->
      let argv = [| "git"; "push"; "origin"; tag |] in
      match run_command_argv argv with
      | Ok _ -> Ok ()
      | Error e -> Error ("Failed to push git tag: " ^ e)
