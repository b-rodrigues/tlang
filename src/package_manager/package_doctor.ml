(* src/package_manager/package_doctor.ml *)
(* Implementation of `t doctor` for package validation *)

type issue_level = Error | Warning | Suggestion

type issue = {
  level : issue_level;
  message : string;
  suggestion : string option;
}

let check_file_exists path description =
  if not (Sys.file_exists path) then
    Some {
      level = Error;
      message = Printf.sprintf "Missing %s: %s" description path;
      suggestion = Some (Printf.sprintf "Create %s" path);
    }
  else None

let check_directory_exists path description =
  if Sys.file_exists path && not (Sys.is_directory path) then
    Some {
      level = Error;
      message = Printf.sprintf "%s is not a directory: %s" description path;
      suggestion = Some (Printf.sprintf "Remove %s and create it as a directory" path);
    }
  else if not (Sys.file_exists path) then
    Some {
      level = Warning;
      message = Printf.sprintf "Missing %s directory: %s" description path;
      suggestion = Some (Printf.sprintf "mkdir %s" path);
    }
  else None

let check_files_in_dir dir pattern description =
  if Sys.file_exists dir && Sys.is_directory dir then
    let entries = Sys.readdir dir in
    let matched = Array.exists (fun e -> 
      (* Simple suffix check for now *)
      String.length e >= String.length pattern &&
      String.sub e (String.length e - String.length pattern) (String.length pattern) = pattern
    ) entries in
    if not matched then
      Some {
        level = Warning;
        message = Printf.sprintf "No %s found in %s" description dir;
        suggestion = None;
      }
    else None
  else None

let validate_package_structure dir =
  let issues = ref [] in
  let add_issue = function
    | Some i -> issues := i :: !issues
    | None -> ()
  in

  (* Check config files *)
  add_issue (check_file_exists (Filename.concat dir "DESCRIPTION.toml") "package configuration");
  add_issue (check_file_exists (Filename.concat dir "flake.nix") "Nix flake definition");

  (* Check directories *)
  add_issue (check_directory_exists (Filename.concat dir "src") "source");
  add_issue (check_directory_exists (Filename.concat dir "tests") "tests");

  (* Check content *)
  add_issue (check_files_in_dir (Filename.concat dir "src") ".t" "T source files");
  add_issue (check_files_in_dir (Filename.concat dir "tests") ".t" "test files");

  (* Check optional but recommended files *)
  let readme = Filename.concat dir "README.md" in
  if not (Sys.file_exists readme) then
    add_issue (Some {
      level = Suggestion;
      message = "No README.md found";
      suggestion = Some "Create a README.md to document your package";
    });

  let license = Filename.concat dir "LICENSE" in
  if not (Sys.file_exists license) then
    add_issue (Some {
      level = Warning;
      message = "No LICENSE file found";
      suggestion = Some "Add a LICENSE file to clarify usage rights";
    });

  List.rev !issues

let validate_project_structure dir =
  let issues = ref [] in
  let add_issue = function
    | Some i -> issues := i :: !issues
    | None -> ()
  in

  add_issue (check_file_exists (Filename.concat dir "tproject.toml") "project configuration");
  add_issue (check_file_exists (Filename.concat dir "flake.nix") "Nix flake definition");
  add_issue (check_directory_exists (Filename.concat dir "src") "source");
  add_issue (check_directory_exists (Filename.concat dir "data") "data");
  add_issue (check_directory_exists (Filename.concat dir "outputs") "outputs");

  List.rev !issues

let check_nix_installation () =
  let code = Sys.command "command -v nix >/dev/null 2>&1" in
  if code <> 0 then
    Some {
      level = Error;
      message = "Nix is not installed or not in PATH";
      suggestion = Some "Install Nix: https://nixos.org/download.html";
    }
  else None

let check_julia_binary () =
  let code = Sys.command "command -v julia >/dev/null 2>&1" in
  if code <> 0 then
    Some {
      level = Warning;
      message = "Julia binary is not installed or not in PATH";
      suggestion = Some "Install Julia and ensure `julia` is available on PATH";
    }
  else None

let check_julia_version () =
  if Sys.command "command -v julia >/dev/null 2>&1" <> 0 then None
  else
    let ic = Unix.open_process_in "julia --version 2>/dev/null" in
    let line = try input_line ic with End_of_file -> "" in
    let status = Unix.close_process_in ic in
    let parse_major_minor version =
      try
        match String.split_on_char '.' version with
        | major :: minor :: _ -> Some (int_of_string major, int_of_string minor)
        | _ -> None
      with _ -> None
    in
    match status with
    | Unix.WEXITED 0 ->
        let version =
          match String.split_on_char ' ' line with
          | _prefix :: v :: _ -> v
          | _ -> ""
        in
        begin match parse_major_minor version with
        | Some (major, minor) when major > 1 || (major = 1 && minor >= 6) -> None
        | Some _ ->
            Some {
              level = Warning;
              message = Printf.sprintf "Julia version %s may be too old; expected Julia >= 1.6" version;
              suggestion = Some "Upgrade Julia to version 1.6 or newer";
            }
        | None ->
            Some {
              level = Suggestion;
              message = Printf.sprintf "Could not parse Julia version output: %s" line;
              suggestion = Some "Run `julia --version` and verify it reports a version >= 1.6";
            }
        end
    | _ ->
        Some {
          level = Suggestion;
          message = "Could not determine Julia version";
          suggestion = Some "Run `julia --version` manually";
        }

let check_julia_load_path () =
  match Sys.getenv_opt "JULIA_LOAD_PATH" with
  | None ->
      Some {
        level = Suggestion;
        message = "JULIA_LOAD_PATH is not set";
        suggestion = Some "Set JULIA_LOAD_PATH so Julia can discover required companion packages";
      }
  | Some load_path when String.trim load_path = "" ->
      Some {
        level = Warning;
        message = "JULIA_LOAD_PATH is empty";
        suggestion = Some "Set JULIA_LOAD_PATH to include Julia project/package paths";
      }
  | Some _ -> None

let check_julia_packages () =
  if Sys.command "command -v julia >/dev/null 2>&1" <> 0 then []
  else
    let required_packages = [ "JSON"; "DataFrames"; "CSV"; "Arrow" ] in
    List.filter_map (fun pkg ->
      let cmd =
        Printf.sprintf
          "julia -e 'import Pkg; has = any(d->d.name==\"%s\", values(Pkg.dependencies())); exit(has ? 0 : 1)' >/dev/null 2>&1"
          pkg
      in
      if Sys.command cmd = 0 then None
      else
        Some {
          level = Warning;
          message = Printf.sprintf "Missing Julia package `%s`" pkg;
          suggestion = Some (Printf.sprintf "Install it with Julia Pkg: `julia -e \"import Pkg; Pkg.add(\\\"%s\\\")\"`" pkg);
        }
    ) required_packages

(*
--# Run Package/Project Doctor
--#
--# Validates the structure of a T package or project, checking for required files, directories,
--# valid Nix configuration, and ensuring proper documentation setup.
--#
--# @name run_doctor
--# @return :: Unit Prints the validation results to the console.
--# @family package_manager
--# @export
*)
let run_doctor () =
  let dir = Sys.getcwd () in
  Printf.printf "Running T Doctor in %s...\n\n" dir;

  let is_package = Sys.file_exists (Filename.concat dir "DESCRIPTION.toml") in
  let is_project = Sys.file_exists (Filename.concat dir "tproject.toml") in

  let issues = 
    if is_package then begin
      Printf.printf "Detected T Package.\n";
      validate_package_structure dir
    end else if is_project then begin
      Printf.printf "Detected T Project.\n";
      validate_project_structure dir
    end else begin
      Printf.printf "Neither DESCRIPTION.toml nor tproject.toml found.\n";
      [{
        level = Error;
        message = "Not a T package or project directory";
        suggestion = Some "Run `t init --package` or `t init --project`";
      }]
    end
  in

  let nix_issue = check_nix_installation () in
  let issues = match nix_issue with Some i -> i :: issues | None -> issues in

  (* Check Documentation *)
  let doc_issues = 
    match Documentation_manager.validate_docs dir with
    | Ok () -> []
    | Error msg ->
         [{ level = Warning; message = msg; suggestion = Some "Run `t docs` to debug or create docs/index.md" }]
  in
  let issues = doc_issues @ issues in
  let julia_issues =
    let base_checks = [ check_julia_binary (); check_julia_version (); check_julia_load_path () ] in
    let base_issues = List.filter_map (fun x -> x) base_checks in
    base_issues @ check_julia_packages ()
  in
  let issues = issues @ julia_issues in

  if issues = [] then
    Printf.printf "\n✓ Everything looks good!\n"
  else begin
    Printf.printf "\nFound %d issue%s:\n\n" (List.length issues) (if List.length issues > 1 then "s" else "");
    List.iter (fun i ->
      let label = match i.level with
        | Error -> "\027[31m[ERROR]\027[0m"
        | Warning -> "\027[33m[WARN]\027[0m "
        | Suggestion -> "\027[34m[INFO]\027[0m "
      in
      Printf.printf "%s %s\n" label i.message;
      match i.suggestion with
      | Some s -> Printf.printf "  → Suggestion: %s\n" s
      | None -> ()
    ) issues;
    Printf.printf "\n"
  end
