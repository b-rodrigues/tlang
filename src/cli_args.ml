type path_kind =
  | File
  | Directory

type test_output_format =
  | Human
  | Json
  | Junit

type test_options = {
  verbose : bool;
  format : test_output_format;
  target_dir : string;
  only_patterns : string list;
  not_patterns : string list;
  failfast : bool;
  list_only : bool;
  timeout : float option;
  coverage : bool;
}

type mode_parse = {
  args : string list;
  mode : Typecheck.mode;
  mode_flag : bool;
  failfast : bool;
}

(** Validate that a file system path exists and matches the expected kind.
    
    @param kind The expected kind (File or Directory).
    @param path The path string to validate.
    @return [Ok ()] if the path is valid and matches the kind, or [Error message] explaining the issue. *)
let validate_path ~kind path =
  let kind_name = function
    | File -> "File"
    | Directory -> "Directory"
  in
  try
    if path = "" then
      Error (Printf.sprintf "%s path must not be empty." (kind_name kind))
    else if not (Sys.file_exists path) then
      Error (Printf.sprintf "%s not found: %s" (kind_name kind) path)
    else
      let is_directory = Sys.is_directory path in
      match kind with
      | File when is_directory ->
          Error (Printf.sprintf "Expected a file path but received a directory: %s" path)
      | Directory when not is_directory ->
          Error (Printf.sprintf "Expected a directory path but received a file: %s" path)
      | _ -> Ok ()
  with
  | Sys_error msg -> Error msg

(** Parse and extract strictness mode, failfast flags, and regular arguments from a CLI list.
    
    @param args The CLI argument list.
    @return [Ok mode_parse] containing filtered args and parsed flags, or [Error message] on invalid flags. *)
let parse_mode_args (args : string list) : (mode_parse, string) result =
  let rec extract acc mode seen failfast = function
    | [] ->
        Ok {
          args = List.rev acc;
          mode;
          mode_flag = seen;
          failfast;
        }
    | "--mode" :: [] ->
        Error "Missing value for --mode. Use --mode repl|strict"
    | "--mode" :: m :: rest ->
        if seen then
          Error "Duplicate --mode flag. Use --mode repl|strict only once."
        else
          (match Typecheck.mode_of_string m with
           | Some mode' -> extract acc mode' true failfast rest
           | None ->
               Error (Printf.sprintf "Invalid mode '%s'. Use --mode repl|strict" m))
    | "--failfast" :: rest -> extract acc mode seen true rest
    | x :: xs -> extract (x :: acc) mode seen failfast xs
  in
  extract [] Typecheck.Repl false false args

(** Validate that CLI flags are used only in command contexts where they are supported.
    
    @param mode_flag Whether [--mode] was provided.
    @param unsafe_flag Whether [--unsafe] was provided.
    @param failfast_flag Whether [--failfast] was provided.
    @param args The entire CLI arguments list.
    @return [Ok ()] if all flag constraints are met, or [Error message] otherwise. *)
let validate_cli_flags ~mode_flag ~unsafe_flag ~failfast_flag (args : string list) : (unit, string) result =
  let commands = ["run"; "repl"; "test"; "explain"; "init"; "doc"; "doctor"; "docs"; "update"; "publish"; "export_artifacts"; "import_artifacts"; "--help"; "-h"; "--version"; "-v"] in
  let command =
    match args with
    | _ :: "run" :: _ -> Some "run"
    | _ :: "repl" :: _ -> Some "repl"
    | _ :: cmd :: _ when List.mem cmd commands -> Some cmd
    | _ :: file :: _ when String.ends_with ~suffix:".t" file -> Some "run"
    | _ :: ("help" | "--help" | "-h") :: _ -> Some "--help"
    | _ :: ("version" | "--version" | "-v") :: _ -> Some "--version"
    | _ -> None
  in
  let run_expr = (command = Some "run") && List.mem "--expr" args in
  let mode_allowed =
    match command with
    | None
    | Some "repl"
    | Some "run"
    | Some "explain"
    | Some "--help"
    | Some "--version"
    | Some "-h"
    | Some "-v" -> true
    | _ -> false
  in
  let failfast_allowed =
    match command with
    | Some "test" | Some "run" | Some "repl" | Some "explain" -> true
    | None -> true
    | _ -> false
  in
  let unsafe_allowed =
    match command with
    | None | Some "run" | Some "repl" -> true
    | _ -> false
  in
  if unsafe_flag && not unsafe_allowed then
    Error "--unsafe is only valid with `t run <file.t>` or `t` (REPL)."
  else if unsafe_flag && run_expr then
    Error "--unsafe cannot be used with `t run --expr`."
  else if mode_flag && (not mode_allowed) then
    Error "--mode only applies to repl/run/explain."
  else if failfast_flag && not failfast_allowed then
    Error "--failfast only applies to repl/run/explain/test."
  else
    Ok ()

(** Parse arguments for the T-Lang test runner.
    
    @param cwd The current working directory to fallback on.
    @param args The list of arguments to parse.
    @return [Ok test_options] if successfully parsed, or [Error message] on unexpected arguments. *)
let parse_test_args ~cwd (args : string list) : (test_options, string) result =
  let verbose = ref false in
  let format = ref Human in
  let target_dir = ref None in
  let only_patterns = ref [] in
  let not_patterns = ref [] in
  let failfast = ref false in
  let list_only = ref false in
  let timeout = ref None in
  let coverage = ref false in
  let rec parse = function
    | [] ->
        Ok {
          verbose = !verbose;
          format = !format;
          target_dir = (match !target_dir with Some dir -> dir | None -> cwd);
          only_patterns = List.rev !only_patterns;
          not_patterns = List.rev !not_patterns;
          failfast = !failfast;
          list_only = !list_only;
          timeout = !timeout;
          coverage = !coverage;
        }
    | ("--verbose" | "-v") :: rest ->
        verbose := true;
        parse rest
    | "--json" :: rest ->
        format := Json;
        parse rest
    | "--format" :: "json" :: rest ->
        format := Json;
        parse rest
    | "--format" :: "junit" :: rest ->
        format := Junit;
        parse rest
    | "--format" :: fmt :: _ ->
        Error (Printf.sprintf "Unknown format '%s'. Use: json, junit" fmt)
    | "--format" :: [] ->
        Error "Missing value for --format. Use --format json|junit"
    | "--only" :: pat :: rest ->
        only_patterns := pat :: !only_patterns;
        parse rest
    | "--only" :: [] ->
        Error "Missing value for --only"
    | "--not" :: pat :: rest ->
        not_patterns := pat :: !not_patterns;
        parse rest
    | "--not" :: [] ->
        Error "Missing value for --not"
    | "--failfast" :: rest ->
        failfast := true;
        parse rest
    | "--list" :: rest ->
        list_only := true;
        parse rest
    | "--timeout" :: secs :: rest ->
        (match Float.of_string_opt secs with
         | Some s when s > 0.0 ->
             timeout := Some s;
             parse rest
         | _ -> Error (Printf.sprintf "Invalid timeout value: %s (must be a positive number)" secs))
    | "--timeout" :: [] ->
        Error "Missing value for --timeout. Use --timeout <seconds>"
    | "--coverage" :: rest ->
        coverage := true;
        parse rest
    | arg :: _ when String.length arg > 0 && arg.[0] = '-' ->
        Error (Printf.sprintf "Unknown option: %s" arg)
    | arg :: rest ->
        (match !target_dir with
         | None ->
             target_dir := Some arg;
             parse rest
         | Some _ ->
             Error (Printf.sprintf "Unexpected argument: %s" arg))
  in
  parse args
