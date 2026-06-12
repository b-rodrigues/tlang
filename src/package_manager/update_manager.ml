(* src/package_manager/update_manager.ml *)
(* Handles dependency updates: regenerate flake.nix from TOML, then lock *)

open Package_types
open Release_manager

module String_set = Set.Make (String)

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

(** Parse remote tag references from `git ls-remote --tags` output.
    
    @param output The raw standard output from the git command.
    @return A list of parsed tag name strings. *)
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

(** Identify the latest semantic version tag from a list of version tag strings.
    
    @param tags The input list of version tag strings.
    @return [Some latest_tag] or [None] if no valid semver tags found. *)
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

type loaded_dependency_source =
  | Project_config of string * project_config
  | Package_config of string * package_config

type project_dependency_counts = {
  t_dependencies : int;
  r_dependencies : int;
  python_dependencies : int;
  julia_dependencies : int;
  additional_tools : int;
  latex_packages : int;
}

(** Count the dependencies and tools configured in a project config.
    
    @param cfg The project configuration.
    @return A [project_dependency_counts] structure containing the counted values. *)
let project_dependency_counts cfg =
  {
    t_dependencies = List.length cfg.proj_dependencies;
    r_dependencies = List.length cfg.proj_r_dependencies;
    python_dependencies = List.length cfg.proj_py_dependencies;
    julia_dependencies = List.length cfg.proj_julia_dependencies;
    additional_tools = List.length cfg.proj_additional_tools;
    latex_packages = List.length cfg.proj_latex_packages;
  }

(** Pluralize a word based on a count.
    
    @param count The count of items.
    @param singular The singular form of the word.
    @param plural The plural form of the word.
    @return The singular or plural word string. *)
let pluralize count singular plural =
  if count = 1 then singular else plural

(** Format a count with a custom label and correctly pluralized suffix.
    
    @param count The numeric count.
    @param label The label (e.g. "T", "R", "Python").
    @param singular The singular word.
    @param plural The plural word.
    @return Formatted string like "2 T dependencies". *)
let format_labeled_count count label singular plural =
  Printf.sprintf "%d %s %s" count label (pluralize count singular plural)

(** Format a count if it's greater than zero, otherwise return None.
    
    @param count The numeric count.
    @param label The label.
    @param singular The singular word.
    @param plural The plural word.
    @return [Some formatted_string] or [None]. *)
let optional_labeled_count count label singular plural =
  if count > 0 then
    Some (format_labeled_count count label singular plural)
  else
    None

(** Retrieve list of formatted segments describing the project's various dependencies.
    
    @param counts The project dependency counts.
    @return A list of descriptive segments. *)
let project_dependency_count_segments counts =
  let base_segments =
    [
      format_labeled_count counts.t_dependencies "T" "dependency" "dependencies";
      format_labeled_count counts.r_dependencies "R" "dependency" "dependencies";
      format_labeled_count
        counts.python_dependencies
        "Python"
        "dependency"
        "dependencies";
      format_labeled_count
        counts.julia_dependencies
        "Julia"
        "dependency"
        "dependencies";
    ]
  in
  let extra_segments =
    List.filter_map
      (fun segment -> segment)
      [
        optional_labeled_count
          counts.additional_tools
          "additional"
          "tool"
          "tools";
        optional_labeled_count
          counts.latex_packages
          "LaTeX"
          "package"
          "packages";
      ]
  in
  base_segments @ extra_segments

(** Format a list of segments into a grammatically correct comma-separated list with "and".
    
    @param segments The list of text segments to combine.
    @return Grammatically joined string. *)
let format_count_segments segments =
  match segments with
  | [] -> ""
  | [segment] -> segment
  | [first; second] -> first ^ " and " ^ second
  | _ ->
      let reversed = List.rev segments in
      (match reversed with
      | last :: rest_rev ->
          String.concat ", " (List.rev rest_rev) ^ " and " ^ last
          | [] -> "")

(** Format a sync message describing the files and dependencies being synced.
    
    @param cfg The project configuration.
    @return Sync log message. *)
let format_project_sync_message cfg =
  let counts = project_dependency_counts cfg in
  Printf.sprintf
    "Syncing %s from tproject.toml → flake.nix...\n"
    (format_count_segments (project_dependency_count_segments counts))

(** Format a descriptive warning message when no T dependencies are declared.
    
    @param config_name The configuration filename.
    @param cfg The project configuration.
    @return Warning message. *)
let format_no_t_project_dependencies_message config_name cfg =
  let counts = project_dependency_counts cfg in
  let non_t_segments =
    List.filter_map
      (fun segment -> segment)
      [
        optional_labeled_count counts.r_dependencies "R" "dependency" "dependencies";
        optional_labeled_count
          counts.python_dependencies
          "Python"
          "dependency"
          "dependencies";
        optional_labeled_count
          counts.julia_dependencies
          "Julia"
          "dependency"
          "dependencies";
        optional_labeled_count
          counts.additional_tools
          "additional"
          "tool"
          "tools";
        optional_labeled_count
          counts.latex_packages
          "LaTeX"
          "package"
          "packages";
      ]
  in
  if non_t_segments = [] then
    Printf.sprintf "No T package dependencies declared in %s.\n" config_name
  else
    Printf.sprintf
      "No T package dependencies declared in %s; project defines %s.\n"
      config_name
      (format_count_segments non_t_segments)

(** Load dependency metadata from the current working directory's TOML configuration.
    Looks for tproject.toml first, then fallbacks to DESCRIPTION.toml.
    
    @return [Ok loaded_dependency_source] or [Error message]. *)
let load_current_dependency_source () =
  let dir = Sys.getcwd () in
  let tproject_path = Filename.concat dir "tproject.toml" in
  let description_path = Filename.concat dir "DESCRIPTION.toml" in
  if Sys.file_exists tproject_path then
    match read_file tproject_path with
    | Error msg -> Error (Printf.sprintf "Cannot read tproject.toml: %s" msg)
    | Ok content ->
        (match Toml_parser.parse_tproject_toml content with
        | Error msg -> Error (Printf.sprintf "Cannot parse tproject.toml: %s" msg)
        | Ok cfg -> Ok (Project_config ("tproject.toml", cfg)))
  else if Sys.file_exists description_path then
    match read_file description_path with
    | Error msg -> Error (Printf.sprintf "Cannot read DESCRIPTION.toml: %s" msg)
    | Ok content ->
        (match Toml_parser.parse_description_toml content with
        | Error msg -> Error (Printf.sprintf "Cannot parse DESCRIPTION.toml: %s" msg)
        | Ok cfg -> Ok (Package_config ("DESCRIPTION.toml", cfg)))
  else
    Error "No tproject.toml or DESCRIPTION.toml found in the current directory."

(** Validate if a Git repository URL/path is safe to execute (no hidden flags or control chars).
    
    @param url The git URL/path string.
    @return [true] if safe, [false] otherwise. *)
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

(** Run git ls-remote to query available tags for a given remote repository.
    
    @param url Safe repository URL/path.
    @return [Ok output] or [Error message]. *)
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

(** Format a user-friendly warning message for various git ls-remote tag check failures.
    
    @param dep_name The dependency name.
    @param reason The underlying failure reason.
    @return Warning message string. *)
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

(** Query the remote repository for a dependency to see if a newer version tag is available.
    
    @param dep The dependency structure to check.
    @return [Some remote_tag_update] if a newer version is found, otherwise [None]. *)
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

(** Scan all declared dependencies in the current project/package configuration for updates.
    
    @return [Ok list_of_updates] or [Error message]. *)
let check_remote_tags () =
  match load_current_dependency_source () with
  | Error msg -> Error msg
  | Ok source ->
      let config_name, deps, no_deps_message =
        match source with
        | Project_config (config_name, cfg) ->
            ( config_name,
              cfg.proj_dependencies,
              format_no_t_project_dependencies_message config_name cfg )
        | Package_config (config_name, cfg) ->
            ( config_name,
              cfg.dependencies,
              Printf.sprintf "No T package dependencies declared in %s.\n" config_name )
      in
      if deps = [] then begin
        Printf.printf "%s" no_deps_message;
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

(** Validate git environment preconditions before attempting to perform dependency updates.
    
    @return [Ok ()] if environment is ready, [Error message] otherwise. *)
let validate_update_prerequisites () =
  let in_ci =
    match Sys.getenv_opt "CI" with
    | Some s when String.trim s <> "" -> true
    | _ -> false
  in
  if in_ci then Ok ()
  else
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

(** Remove the trailing JSON comma from a pretty-printed flake.lock field value. *)
let trim_trailing_comma value =
  let value = String.trim value in
  let len = String.length value in
  if len > 0 && value.[len - 1] = ',' then
    String.sub value 0 (len - 1)
  else
    value

(** Normalize a pretty-printed flake.lock field value by trimming commas and quotes. *)
let normalize_json_value value =
  let trimmed = trim_trailing_comma value in
  let len = String.length trimmed in
  if len >= 2 && trimmed.[0] = '"' && trimmed.[len - 1] = '"' then
    String.sub trimmed 1 (len - 2)
  else
    trimmed

(** Finalize the current lock node parsing state, moving it to the parsed nodes list.
    
    @param state Current parser state.
    @return Updated parser state. *)
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

(** Parse the top-level nodes from flake.lock's standard pretty-printed JSON output.
    This expects nix's usual indentation for nodes and locked/original sections
    (2/4/6/8 spaces respectively). *)
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

(** Find a parsed flake lock node snapshot by its input name.
    
    @param name Input/dependency name.
    @param nodes List of parsed lock nodes.
    @return [Some node] if found, otherwise [None]. *)
let find_flake_lock_node name nodes =
  List.find_opt (fun node -> node.name = name) nodes

(** Look up a field's value in a list of key-value fields.
    
    @param fields List of fields.
    @param key The field key.
    @return [Some value] if found, otherwise [None]. *)
let field_value fields key = List.assoc_opt key fields

(** Collect unique projected string values from multiple lists while preserving
    first-seen order across the input lists. *)
let collect_unique_ordered_by project lists =
  let _, reversed =
    List.fold_left
      (fun (seen, acc) items ->
        List.fold_left
          (fun (seen, acc) item ->
            let value = project item in
            if String_set.mem value seen then
              (seen, acc)
            else
              (String_set.add value seen, value :: acc))
          (seen, acc)
          items)
      (String_set.empty, [])
      lists
  in
  List.rev reversed

(** Compare the content of a flake.lock file before and after updating, and generate a human-readable list of changes.
    
    @param before_content Optional string content of flake.lock before updating.
    @param after_content Optional string content of flake.lock after updating.
    @return A list of strings describing identified changes. *)
let summarize_flake_lock_changes before_content after_content =
  match before_content, after_content with
  | None, None -> []
  | None, Some _ -> [ "  - flake.lock created." ]
  | Some before, Some after when before = after -> []
  | Some before, Some after ->
      let before_nodes = parse_flake_lock_nodes before in
      let after_nodes = parse_flake_lock_nodes after in
      let node_names = collect_unique_ordered_by (fun node -> node.name) [before_nodes; after_nodes] in
      let describe_field_changes section_name before_fields after_fields =
        let field_names = collect_unique_ordered_by fst [before_fields; after_fields] in
        List.fold_left
          (fun acc field_name ->
            match field_value before_fields field_name, field_value after_fields field_name with
            | Some before_value, Some after_value when before_value <> after_value ->
                Printf.sprintf
                  "      %s.%s: %s -> %s"
                  section_name
                  field_name
                  before_value
                  after_value
                :: acc
            | None, Some after_value ->
                Printf.sprintf
                  "      %s.%s: (missing) -> %s"
                  section_name
                  field_name
                  after_value
                :: acc
            | Some before_value, None ->
                Printf.sprintf
                  "      %s.%s: %s -> (missing)"
                  section_name
                  field_name
                  before_value
                :: acc
            | _ -> acc)
          []
          field_names
        |> List.rev
      in
      let lines =
        List.fold_left
          (fun acc node_name ->
            match find_flake_lock_node node_name before_nodes, find_flake_lock_node node_name after_nodes with
            | None, Some _ -> Printf.sprintf "  - %s: added to flake.lock" node_name :: acc
            | Some _, None -> Printf.sprintf "  - %s: removed from flake.lock" node_name :: acc
            | Some before_node, Some after_node ->
                let node_changes =
                  describe_field_changes "original" before_node.original_fields after_node.original_fields
                  @ describe_field_changes "locked" before_node.locked_fields after_node.locked_fields
                in
                if node_changes = [] then
                  acc
                else
                  List.rev_append (Printf.sprintf "  - %s" node_name :: node_changes) acc
            | None, None -> acc)
          []
          node_names
        |> List.rev
      in
      if lines = [] then [ "  - flake.lock changed." ] else lines
  | Some _, None -> [ "  - flake.lock was removed." ]

(** Print a report of the differences/changes detected in flake.lock.
    
    @param before_content Optional string content before updates.
    @param after_content Optional string content after updates. *)
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
       | None -> Nixpkgs_date.date) (* Changed fallback to static rstats-on-nix date *)
     | Error _ -> Nixpkgs_date.date
   in
  let in_ci = (match Sys.getenv_opt "CI" with Some s when String.trim s <> "" -> true | _ -> false) in
  (* On CI, we want to pinned to the versions being tested: specifically the nixpkgs date
     from the current T source, and the T-lang flake pointing to the repo/SHA under test. *)
  let nixpkgs_date = if in_ci then Nixpkgs_date.date else nixpkgs_date in
  (if in_ci then (
     match Sys.getenv_opt "TLANG_REPO", Sys.getenv_opt "TLANG_SHA" with
     | Some repo, Some sha ->
         Unix.putenv "TLANG_FLAKE_URL" (Printf.sprintf "github:%s/%s" repo sha)
     | _ -> ()
  ));
  let flake_lock_before =
    if Sys.file_exists flake_lock_path then
      match read_file flake_lock_path with
      | Ok content -> Some content
      | Error _ -> None
    else
      None
  in
  match check_remote_tags () with
  | Error msg -> Error msg
  | Ok _ ->
      match validate_update_prerequisites () with
      | Error msg -> Error msg
      | Ok () ->
          let regen_result =
            if Sys.file_exists tproject_path then begin
              match read_file tproject_path with
              | Error msg -> Error (Printf.sprintf "Cannot read tproject.toml: %s" msg)
              | Ok content ->
                  match Toml_parser.parse_tproject_toml content with
                  | Error msg -> Error (Printf.sprintf "Cannot parse tproject.toml: %s" msg)
                  | Ok cfg ->
                      Printf.printf "%s" (format_project_sync_message cfg);
                      flush stdout;
                      match Nix_generator.install_flake
                              ~kind:Project
                              ~name:cfg.proj_name
                              ~version:"0.0.0"
                              ~nixpkgs_date:(if cfg.proj_nixpkgs_date <> "" then cfg.proj_nixpkgs_date else nixpkgs_date)
                              ~t_version:cfg.proj_min_t_version
                              ~deps:cfg.proj_dependencies
                              ~r_deps:cfg.proj_r_dependencies
                              ~py_deps:cfg.proj_py_dependencies
                              ~py_version:cfg.proj_py_version
                              ~jl_deps:cfg.proj_julia_dependencies
                              ~jl_version:cfg.proj_julia_version
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
                              ~nixpkgs_date:nixpkgs_date
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
              let in_ci = (match Sys.getenv_opt "CI" with Some s when String.trim s <> "" -> true | _ -> false) in
              (if in_ci then ignore (run_command "git add -N flake.nix 2>/dev/null || true"));
              let update_cmd = if in_ci then "nix flake lock --accept-flake-config" else "nix flake update --accept-flake-config" in
              match run_command update_cmd with
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

(** Upgrade the current project to the latest T version and today's nixpkgs date *)
let cmd_upgrade () =
  let dir = Sys.getcwd () in
  let tproject_path = Filename.concat dir "tproject.toml" in
  if not (Sys.file_exists tproject_path) then
    Error "tproject.toml not found. Upgrade is only supported for projects."
  else
    match read_file tproject_path with
    | Error msg -> Error (Printf.sprintf "Cannot read tproject.toml: %s" msg)
    | Ok content ->
        match Toml_parser.parse_tproject_toml content with
        | Error msg -> Error (Printf.sprintf "Cannot parse tproject.toml: %s" msg)
        | Ok cfg ->
            Printf.printf "Checking for new T releases...\n";
            flush stdout;
            let latest_tag = Scaffold.latest_tlang_tag () in
            let latest_version = Scaffold.strip_v_prefix latest_tag in
            
            let t = Unix.gmtime (Unix.gettimeofday ()) in
            let today = Printf.sprintf "%04d-%02d-%02d" (1900 + t.Unix.tm_year) (t.Unix.tm_mon + 1) t.Unix.tm_mday in
            
            if cfg.proj_min_t_version = latest_version && cfg.proj_nixpkgs_date = today then (
              Printf.printf "Project is already up to date (T %s, nixpkgs %s).\n" latest_version today;
              Ok ()
            ) else (
              Printf.printf "Upgrading project to T %s and nixpkgs date %s...\n" latest_version today;
              flush stdout;
              let new_cfg = { cfg with proj_min_t_version = latest_version; proj_nixpkgs_date = today } in
              let new_content = Toml_parser.serialize_tproject_toml new_cfg in
              try
                let oc = open_out tproject_path in
                Fun.protect
                  ~finally:(fun () -> close_out_noerr oc)
                  (fun () -> output_string oc new_content);
                Printf.printf "Regenerating flake.nix and updating dependencies...\n";
                flush stdout;
                update_flake_lock ()
              with e -> Error (Printf.sprintf "Failed to update tproject.toml: %s" (Printexc.to_string e))
            )
