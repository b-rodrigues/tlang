(* src/package_manager/update_manager.ml *)
(* Handles dependency updates: regenerate flake.nix from TOML, then lock *)

open Package_types
open Release_manager

type remote_tag_update = {
  dependency_name : string;
  current_tag : string;
  latest_tag : string;
}

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

let parse_remote_tag_refs output =
  let prefix = "refs/tags/" in
  let prefix_len = String.length prefix in
  output
  |> String.split_on_char '\n'
  |> List.fold_left
       (fun acc line ->
         match String.split_on_char '\t' (String.trim line) with
         | [_sha; refname] when String.starts_with ~prefix refname ->
             let tag = String.sub refname prefix_len (String.length refname - prefix_len) in
             if String.ends_with ~suffix:"^{}" tag then
               acc
             else
               tag :: acc
         | _ -> acc)
       []
  |> List.rev

let latest_semver_tag tags =
  let versioned_tags =
    List.fold_left
      (fun acc tag ->
        match Scaffold.parse_semver tag with
        | Some semver -> (semver, tag) :: acc
        | None -> acc)
      []
      tags
  in
  match versioned_tags with
  | [] -> None
  | (semver, tag) :: rest ->
      let _, latest_tag =
        List.fold_left
          (fun (best_semver, best_tag) (candidate_semver, candidate_tag) ->
            if Scaffold.compare_semver candidate_semver best_semver > 0 then
              (candidate_semver, candidate_tag)
            else
              (best_semver, best_tag))
          (semver, tag)
          rest
      in
      Some latest_tag

let load_current_dependencies () =
  let dir = Sys.getcwd () in
  let tproject_path = Filename.concat dir "tproject.toml" in
  let description_path = Filename.concat dir "DESCRIPTION.toml" in
  if Sys.file_exists tproject_path then
    match read_file tproject_path with
    | Error msg -> Error (Printf.sprintf "Cannot read tproject.toml: %s" msg)
    | Ok content ->
        (match Toml_parser.parse_tproject_toml content with
        | Error msg -> Error (Printf.sprintf "Cannot parse tproject.toml: %s" msg)
        | Ok cfg -> Ok ("tproject.toml", cfg.proj_dependencies))
  else if Sys.file_exists description_path then
    match read_file description_path with
    | Error msg -> Error (Printf.sprintf "Cannot read DESCRIPTION.toml: %s" msg)
    | Ok content ->
        (match Toml_parser.parse_description_toml content with
        | Error msg -> Error (Printf.sprintf "Cannot parse DESCRIPTION.toml: %s" msg)
        | Ok cfg -> Ok ("DESCRIPTION.toml", cfg.dependencies))
  else
    Error "No tproject.toml or DESCRIPTION.toml found in the current directory."

let is_safe_git_location url =
  let len = String.length url in
  let rec check i =
    if i >= len then
      true
    else
      match url.[i] with
      | '\000' | '\n' | '\r' -> false
      | _ -> check (i + 1)
  in
  len > 0 && url.[0] <> '-' && check 0

let run_git_ls_remote_tags url =
  if not (is_safe_git_location url) then
    Error "invalid repository location"
  else
    try
      let argv = [| "git"; "ls-remote"; "--tags"; url |] in
      let ch_in, ch_out, ch_err =
        Unix.open_process_args_full "git" argv (Unix.environment ())
      in
      close_out ch_out;
      let out_buf = Buffer.create 1024 in
      let err_buf = Buffer.create 1024 in
      let buf = Bytes.create 4096 in
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
              let n =
                try input ch_in buf 0 (Bytes.length buf) with
                | End_of_file -> 0
              in
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
              let n =
                try input ch_err buf 0 (Bytes.length buf) with
                | End_of_file -> 0
              in
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
      | Unix.WEXITED _ ->
          let err_output = String.trim (Buffer.contents err_buf) in
          let lower_err = String.lowercase_ascii err_output in
          if err_output = "" then
            Error "git ls-remote failed"
          else if String.starts_with ~prefix:"fatal" lower_err then
            Error "repository access failed"
          else
            Error "git ls-remote reported an error"
      | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> Error "git ls-remote terminated unexpectedly"
    with _ -> Error "git ls-remote invocation failed"

let remote_tag_warning_message dep_name reason =
  match reason with
  | "invalid repository location" ->
      Printf.sprintf
        "Warning: Failed to check remote tags for `%s`. Verify the dependency git location in your TOML file.\n%!"
        dep_name
  | "repository access failed" ->
      Printf.sprintf
        "Warning: Failed to check remote tags for `%s`. Verify the repository URL and your access to it.\n%!"
        dep_name
  | _ ->
      Printf.sprintf
        "Warning: Failed to check remote tags for `%s`. Verify git is available and try again.\n%!"
        dep_name

let check_dependency_remote_tag dep =
  match Scaffold.parse_semver dep.tag with
  | None -> None
  | Some current_semver ->
      match run_git_ls_remote_tags dep.git_url with
      | Error msg ->
          Printf.eprintf "%s" (remote_tag_warning_message dep.dep_name msg);
          None
      | Ok output ->
          match latest_semver_tag (parse_remote_tag_refs output) with
          | None -> None
          | Some latest_tag ->
              (match Scaffold.parse_semver latest_tag with
              | Some latest_semver when Scaffold.compare_semver latest_semver current_semver > 0 ->
                  Some
                    {
                      dependency_name = dep.dep_name;
                      current_tag = dep.tag;
                      latest_tag;
                    }
              | _ -> None)

let check_remote_tags () =
  match load_current_dependencies () with
  | Error msg -> Error msg
  | Ok (config_name, deps) ->
      if deps = [] then begin
        Printf.printf "No T package dependencies declared in %s.\n" config_name;
        flush stdout;
        Ok []
      end else
        let updates =
          List.fold_left
            (fun acc dep ->
              match check_dependency_remote_tag dep with
              | Some update -> update :: acc
              | None -> acc)
            []
            deps
          |> List.rev
        in
        if updates = [] then
          Printf.printf "All pinned dependency tags in %s are up to date.\n" config_name
        else begin
          Printf.printf
            "Newer tagged releases are available in %s:\n"
            config_name;
          List.iter
            (fun update ->
              Printf.printf "  - %s: %s -> %s\n"
                update.dependency_name
                update.current_tag
                update.latest_tag)
            updates
        end;
        flush stdout;
        Ok updates

let validate_update_prerequisites () =
  match validate_git_remote () with
  | Error _ as err -> err
  | Ok () -> validate_clean_git ()

type lock_section =
  | Locked
  | Original

type flake_lock_node_snapshot = {
  name : string;
  locked_fields : (string * string) list;
  original_fields : (string * string) list;
}

type flake_lock_parse_state = {
  inside_nodes : bool;
  current_node : string option;
  current_section : lock_section option;
  current_locked : (string * string) list;
  current_original : (string * string) list;
  nodes : flake_lock_node_snapshot list;
}

let trim_trailing_comma value =
  let trimmed = String.trim value in
  let len = String.length trimmed in
  if len > 0 && trimmed.[len - 1] = ',' then
    String.sub trimmed 0 (len - 1)
  else
    trimmed

let normalize_json_value value =
  let trimmed = trim_trailing_comma value in
  let len = String.length trimmed in
  if len >= 2 && trimmed.[0] = '"' && trimmed.[len - 1] = '"' then
    String.sub trimmed 1 (len - 2)
  else
    trimmed

let finalize_current_node state =
  match state.current_node with
  | None -> state
  | Some name ->
      {
        state with
        current_node = None;
        current_locked = [];
        current_original = [];
        nodes =
          {
            name;
            locked_fields = List.rev state.current_locked;
            original_fields = List.rev state.current_original;
          }
          :: state.nodes;
      }

let parse_flake_lock_nodes content =
  let lines = String.split_on_char '\n' content in
  let nodes_start_re = Str.regexp {|^  "nodes": {$|} in
  let node_re = Str.regexp {|^    "\([^"]+\)": {$|} in
  let subsection_re = Str.regexp {|^      "\(locked\|original\)": {$|} in
  let field_re = Str.regexp {|^        "\([^"]+\)": \(.*\)$|} in
  let initial_state =
    {
      inside_nodes = false;
      current_node = None;
      current_section = None;
      current_locked = [];
      current_original = [];
      nodes = [];
    }
  in
  let final_state =
    List.fold_left
      (fun state line ->
        if (not state.inside_nodes) && Str.string_match nodes_start_re line 0 then
          { state with inside_nodes = true }
        else if state.inside_nodes then
          match state.current_node, state.current_section with
          | None, _ when line = "  }," || line = "  }" ->
              { state with inside_nodes = false }
          | Some _, Some _ when line = "      }," || line = "      }" ->
              { state with current_section = None }
          | Some _, None when line = "    }," || line = "    }" ->
              finalize_current_node state
          | None, _ when Str.string_match node_re line 0 ->
              {
                state with
                current_node = Some (Str.matched_group 1 line);
                current_section = None;
                current_locked = [];
                current_original = [];
              }
          | Some _, None when Str.string_match subsection_re line 0 ->
              let section_name = Str.matched_group 1 line in
              let current_section =
                if section_name = "locked" then Some Locked else Some Original
              in
              { state with current_section }
          | Some _, Some section when Str.string_match field_re line 0 ->
              let key = Str.matched_group 1 line in
              let value = normalize_json_value (Str.matched_group 2 line) in
              (match section with
              | Locked ->
                  { state with current_locked = (key, value) :: state.current_locked }
              | Original ->
                  {
                    state with
                    current_original = (key, value) :: state.current_original;
                  })
          | _ -> state
        else
          state)
      initial_state
      lines
  in
  let final_state = finalize_current_node final_state in
  List.rev final_state.nodes

let find_flake_lock_node name nodes =
  List.find_opt (fun node -> node.name = name) nodes

let field_value fields key = List.assoc_opt key fields

let append_unique value values =
  if List.mem value values then values else values @ [value]

let summarize_flake_lock_changes before_content after_content =
  match before_content, after_content with
  | None, None -> []
  | None, Some _ -> [ "  - flake.lock created." ]
  | Some before, Some after when before = after -> []
  | Some before, Some after ->
      let before_nodes = parse_flake_lock_nodes before in
      let after_nodes = parse_flake_lock_nodes after in
      let node_names =
        List.fold_left
          (fun acc node -> append_unique node.name acc)
          []
          (before_nodes @ after_nodes)
      in
      let describe_field_changes section_name before_fields after_fields =
        let field_names =
          List.fold_left
            (fun acc (key, _) -> append_unique key acc)
            []
            (before_fields @ after_fields)
        in
        List.fold_left
          (fun acc field_name ->
            match field_value before_fields field_name, field_value after_fields field_name with
            | Some before_value, Some after_value when before_value <> after_value ->
                acc
                @
                [
                  Printf.sprintf
                    "      %s.%s: %s -> %s"
                    section_name
                    field_name
                    before_value
                    after_value;
                ]
            | None, Some after_value ->
                acc
                @
                [
                  Printf.sprintf
                    "      %s.%s: (missing) -> %s"
                    section_name
                    field_name
                    after_value;
                ]
            | Some before_value, None ->
                acc
                @
                [
                  Printf.sprintf
                    "      %s.%s: %s -> (missing)"
                    section_name
                    field_name
                    before_value;
                ]
            | _ -> acc)
          []
          field_names
      in
      let lines =
        List.fold_left
          (fun acc node_name ->
            match find_flake_lock_node node_name before_nodes, find_flake_lock_node node_name after_nodes with
            | None, Some _ -> acc @ [Printf.sprintf "  - %s: added to flake.lock" node_name]
            | Some _, None -> acc @ [Printf.sprintf "  - %s: removed from flake.lock" node_name]
            | Some before_node, Some after_node ->
                let node_changes =
                  describe_field_changes "original" before_node.original_fields after_node.original_fields
                  @ describe_field_changes "locked" before_node.locked_fields after_node.locked_fields
                in
                if node_changes = [] then
                  acc
                else
                  acc @ (Printf.sprintf "  - %s" node_name :: node_changes)
            | None, None -> acc)
          []
          node_names
      in
      if lines = [] then [ "  - flake.lock changed." ] else lines
  | Some _, None -> [ "  - flake.lock was removed." ]

let report_flake_lock_changes before_content after_content =
  let summary_lines = summarize_flake_lock_changes before_content after_content in
  if summary_lines = [] then
    Printf.printf "flake.lock is already up to date.\n"
  else begin
    Printf.printf "flake.lock changes:\n";
    List.iter (fun line -> Printf.printf "%s\n" line) summary_lines
  end;
  flush stdout

(*
--# Update Dependencies
--#
--# Regenerates the `flake.nix` file from the current TOML configuration and runs `nix flake update`
--# to lock dependencies to their latest versions within the specified tags.
--#
--# @name update_flake_lock
--# @return :: Result[Unit] Ok(()) or an error message.
--# @family package_manager
--# @export
*)
let update_flake_lock () =
  let dir = Sys.getcwd () in
  let tproject_path = Filename.concat dir "tproject.toml" in
  let description_path = Filename.concat dir "DESCRIPTION.toml" in
  let flake_path = Filename.concat dir "flake.nix" in
  let flake_lock_path = Filename.concat dir "flake.lock" in
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
  let flake_lock_before =
    if Sys.file_exists flake_lock_path then
      match read_file flake_lock_path with
      | Ok content -> Some content
      | Error _ -> None
    else
      None
  in
  match validate_update_prerequisites () with
  | Error msg -> Error msg
  | Ok () ->
      match check_remote_tags () with
      | Error msg -> Error msg
      | Ok _ ->
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
                              ~r_deps:cfg.proj_r_dependencies
                              ~py_deps:cfg.proj_py_dependencies
                              ~py_version:cfg.proj_py_version
                              ~additional_tools:cfg.proj_additional_tools
                              ~latex_pkgs:cfg.proj_latex_packages
                              ~dir
                              ~dry_run:false
                              ()
                      with
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
                              ~additional_tools:cfg.additional_tools
                              ~latex_pkgs:cfg.latex_packages
                              ~dir
                              ~dry_run:false
                              ()
                      with
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
              match run_command "nix flake update --accept-flake-config" with
              | Ok _ ->
                  let flake_lock_after =
                    if Sys.file_exists flake_lock_path then
                      match read_file flake_lock_path with
                      | Ok content -> Some content
                      | Error _ -> None
                    else
                      None
                  in
                  report_flake_lock_changes flake_lock_before flake_lock_after;
                  Ok ()
              | Error msg -> Error ("Failed to update dependencies: " ^ msg)
