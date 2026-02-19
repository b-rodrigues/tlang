(* src/package_manager/update_manager.ml *)
(* Handles dependency updates: regenerate flake.nix from TOML, then lock *)

open Package_types
open Release_manager

(** Extract the nixpkgs date from an existing flake.nix by looking for
    the pattern "rstats-on-nix/nixpkgs/YYYY-MM-DD" *)
let extract_nixpkgs_date flake_content =
  let prefix = "rstats-on-nix/nixpkgs/" in
  let plen = String.length prefix in
  let rec search i =
    if i + plen + 10 > String.length flake_content then None
    else if String.sub flake_content i plen = prefix then
      let date = String.sub flake_content (i + plen) 10 in
      (* Basic sanity check: YYYY-MM-DD *)
      if String.length date = 10 && date.[4] = '-' && date.[7] = '-' then
        Some date
      else
        search (i + 1)
    else
      search (i + 1)
  in
  search 0

(** Read a file's contents *)
let read_file path =
  try
    let ch = open_in path in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    Ok content
  with Sys_error msg -> Error msg

(** Detect whether the current directory is a project or package,
    parse its TOML config and dependencies, regenerate flake.nix,
    then run 'nix flake update' to lock inputs. *)
let update_flake_lock () =
  let dir = Sys.getcwd () in
  let tproject_path = Filename.concat dir "tproject.toml" in
  let description_path = Filename.concat dir "DESCRIPTION.toml" in
  let flake_path = Filename.concat dir "flake.nix" in
  (* Read existing flake.nix to extract nixpkgs_date *)
  let nixpkgs_date =
    match read_file flake_path with
    | Ok content ->
      (match extract_nixpkgs_date content with
       | Some date -> date
       | None ->
         let t = Unix.gmtime (Unix.gettimeofday ()) in
         Printf.sprintf "%04d-%02d-%02d" (1900 + t.Unix.tm_year) (t.Unix.tm_mon + 1) t.Unix.tm_mday)
    | Error _ ->
      let t = Unix.gmtime (Unix.gettimeofday ()) in
      Printf.sprintf "%04d-%02d-%02d" (1900 + t.Unix.tm_year) (t.Unix.tm_mon + 1) t.Unix.tm_mday
  in
  (* Detect and regenerate flake.nix *)
  let regen_result =
    if Sys.file_exists tproject_path then begin
      match read_file tproject_path with
      | Error msg -> Error (Printf.sprintf "Cannot read tproject.toml: %s" msg)
      | Ok content ->
        match Toml_parser.parse_tproject_toml content with
        | Error msg -> Error (Printf.sprintf "Cannot parse tproject.toml: %s" msg)
        | Ok cfg ->
          Printf.printf "Syncing %d dependency(ies) from tproject.toml → flake.nix...\n"
            (List.length cfg.proj_dependencies);
          flush stdout;
          match Nix_generator.install_flake
            ~kind:Project
            ~name:cfg.proj_name
            ~version:"0.0.0"
            ~nixpkgs_date
            ~t_version:cfg.proj_min_t_version
            ~deps:cfg.proj_dependencies
            ~dir
            ~dry_run:false with
          | Ok _ -> Ok ()
          | Error msg -> Error msg
    end
    else if Sys.file_exists description_path then begin
      match read_file description_path with
      | Error msg -> Error (Printf.sprintf "Cannot read DESCRIPTION.toml: %s" msg)
      | Ok content ->
        match Toml_parser.parse_description_toml content with
        | Error msg -> Error (Printf.sprintf "Cannot parse DESCRIPTION.toml: %s" msg)
        | Ok cfg ->
          Printf.printf "Syncing %d dependency(ies) from DESCRIPTION.toml → flake.nix...\n"
            (List.length cfg.dependencies);
          flush stdout;
          match Nix_generator.install_flake
            ~kind:Package
            ~name:cfg.name
            ~version:cfg.version
            ~nixpkgs_date
            ~t_version:cfg.min_t_version
            ~deps:cfg.dependencies
            ~dir
            ~dry_run:false with
          | Ok _ -> Ok ()
          | Error msg -> Error msg
    end
    else
      Error "No tproject.toml or DESCRIPTION.toml found in the current directory."
  in
  match regen_result with
  | Error msg -> Error msg
  | Ok () ->
    Printf.printf "Running nix flake update...\n";
    flush stdout;
    match run_command "nix flake update" with
    | Ok _ -> Ok ()
    | Error msg -> Error ("Failed to update dependencies: " ^ msg)

(* Future: check remote tags *)
let check_remote_tags () =
  Printf.printf "Note: Checking for newer tags is not yet implemented. 'nix flake update' will fetch latest commits.\n";
  Ok []
