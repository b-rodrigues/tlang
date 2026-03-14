type path_kind =
  | File
  | Directory

type test_options = {
  verbose : bool;
  target_dir : string;
}

type mode_parse = {
  args : string list;
  mode : Typecheck.mode;
  mode_flag : bool;
}

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

let parse_mode_args (args : string list) : (mode_parse, string) result =
  let rec extract acc mode seen = function
    | [] ->
        Ok {
          args = List.rev acc;
          mode;
          mode_flag = seen;
        }
    | "--mode" :: [] ->
        Error "Missing value for --mode. Use --mode repl|strict"
    | "--mode" :: m :: rest ->
        if seen then
          Error "Duplicate --mode flag. Use --mode repl|strict only once."
        else
          (match Typecheck.mode_of_string m with
           | Some mode' -> extract acc mode' true rest
           | None ->
               Error (Printf.sprintf "Invalid mode '%s'. Use --mode repl|strict" m))
    | x :: xs -> extract (x :: acc) mode seen xs
  in
  extract [] Typecheck.Repl false args

let validate_cli_flags ~mode_flag ~unsafe_flag (args : string list) : (unit, string) result =
  let commands = ["run"; "repl"; "test"; "explain"; "init"; "doc"; "doctor"; "docs"; "update"; "publish"; "--help"; "-h"; "--version"; "-v"] in
  let command =
    match args with
    | _ :: "run" :: _ -> Some "run"
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
  if unsafe_flag && command <> Some "run" then
    Error "--unsafe is only valid with `t run <file.t>`."
  else if unsafe_flag && run_expr then
    Error "--unsafe cannot be used with `t run --expr`."
  else if mode_flag && (not mode_allowed) then
    Error "--mode only applies to repl/run/explain."
  else
    Ok ()

let parse_test_args ~cwd (args : string list) : (test_options, string) result =
  let verbose = ref false in
  let target_dir = ref None in
  let rec parse = function
    | [] ->
        Ok {
          verbose = !verbose;
          target_dir = (match !target_dir with Some dir -> dir | None -> cwd);
        }
    | ("--verbose" | "-v") :: rest ->
        verbose := true;
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
