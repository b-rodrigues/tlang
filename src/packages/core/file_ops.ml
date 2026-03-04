open Ast

let register env =
  (*
  --# Get current working directory
  --#
  --# Returns the absolute path of the current working directory.
  --#
  --# @name getwd
  --# @return :: String The current working directory.
  --# @example
  --#   getwd()
  --# @family core
  --# @export
  *)
  let env = Env.add "getwd"
    (make_builtin_named ~name:"getwd" 0 (fun _args _env ->
      try VString (Sys.getcwd ())
      with Sys_error msg ->
        Error.runtime_error (Printf.sprintf "getwd: %s" msg)
    ))
    env
  in
  (*
  --# Check if file exists
  --#
  --# Checks if a regular file exists at the given path.
  --# Returns false if the path is a directory or does not exist.
  --#
  --# @name file_exists
  --# @param path :: String The path to check.
  --# @return :: Bool True if it's a regular file.
  --# @example
  --#   file_exists("data.csv")
  --# @family core
  --# @export
  *)
  let env = Env.add "file_exists"
    (make_builtin_named ~name:"file_exists" 1 (fun args _env ->
      match args with
      | [(_, VString path)] | [(_, VSymbol path)] ->
          let exists =
            match Unix.stat path with
            | exception Unix.Unix_error _ -> false
            | { Unix.st_kind = Unix.S_REG; _ } -> true
            | _ -> false
          in
          VBool exists
      | [(_, other)] ->
          Error.type_error (Printf.sprintf "Function `file_exists` expects a String, got %s." (Utils.type_name other))
      | _ -> Error.arity_error_named "file_exists" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  (*
  --# Check if directory exists
  --#
  --# Checks if a directory exists at the given path.
  --#
  --# @name dir_exists
  --# @param path :: String The path to check.
  --# @return :: Bool True if it's a directory.
  --# @example
  --#   dir_exists("tests")
  --# @family core
  --# @export
  *)
  let env = Env.add "dir_exists"
    (make_builtin_named ~name:"dir_exists" 1 (fun args _env ->
      match args with
      | [(_, VString path)] | [(_, VSymbol path)] ->
          let exists =
            match Unix.stat path with
            | exception Unix.Unix_error _ -> false
            | { Unix.st_kind = Unix.S_DIR; _ } -> true
            | _ -> false
          in
          VBool exists
      | [(_, other)] ->
          Error.type_error (Printf.sprintf "Function `dir_exists` expects a String, got %s." (Utils.type_name other))
      | _ -> Error.arity_error_named "dir_exists" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  (*
  --# Read file contents
  --#
  --# Reads the entire content of a file into a string.
  --#
  --# @name read_file
  --# @param path :: String The path to the file.
  --# @return :: String The file content.
  --# @example
  --#   read_file("config.json")
  --# @family core
  --# @export
  *)
  let env = Env.add "read_file"
    (make_builtin_named ~name:"read_file" 1 (fun args _env ->
      match args with
      | [(_, VString path)] | [(_, VSymbol path)] ->
          (try
            let ic = open_in path in
            Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
              let n = in_channel_length ic in
              let buf = Bytes.create n in
              really_input ic buf 0 n;
              VString (Bytes.to_string buf)
            )
          with
          | Sys_error msg ->
            Error.make_error FileError (Printf.sprintf "read_file: %s" msg)
          | exn ->
            Error.make_error FileError (Printf.sprintf "read_file: %s" (Printexc.to_string exn)))
      | [(_, other)] ->
          Error.type_error (Printf.sprintf "Function `read_file` expects a String, got %s." (Utils.type_name other))
      | _ -> Error.arity_error_named "read_file" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  (*
  --# List files in directory
  --#
  --# Returns a list of files and directories in the specified path.
  --# Supports an optional regex pattern for filtering.
  --#
  --# @name list_files
  --# @param path :: String [Optional] The directory to list. Defaults to ".".
  --# @param pattern :: String [Optional] Regex pattern to filter results.
  --# @return :: List[String] List of filenames.
  --# @example
  --#   list_files(".", pattern = "\\.t$")
  --# @family core
  --# @export
  *)
  let env = Env.add "list_files"
    (make_builtin_named ~name:"list_files" ~variadic:true 0 (fun args _env ->
      let positional = List.filter (fun (name, _) -> name = None) args in
      let n_positional = List.length positional in
      if n_positional > 1 then
        Error.arity_error_named "list_files" ~expected:1 ~received:n_positional
      else
      let path_result = match positional with
        | [(_, VString s)] | [(_, VSymbol s)] -> Ok s
        | [(_, other)] ->
            Error (Printf.sprintf "Function `list_files` expects a String path, got %s." (Utils.type_name other))
        | _ -> Ok "."
      in
      match path_result with
      | Error msg -> Error.type_error msg
      | Ok path ->
          let pattern_result = match List.assoc_opt (Some "pattern") args with
            | Some (VString s) | Some (VSymbol s) ->
                (match Str.regexp s with
                 | exception Failure msg ->
                     Error (Printf.sprintf "Invalid pattern for `list_files`: %s" msg)
                 | re -> Ok (Some re))
            | None -> Ok None
            | Some other ->
                Error (Printf.sprintf "Argument `pattern` of `list_files` must be a String, got %s." (Utils.type_name other))
          in
          (match pattern_result with
           | Error msg -> Error.type_error msg
           | Ok compiled_pattern ->
               (try
                 let entries = Sys.readdir path in
                 let filenames = Array.to_list entries in
                 let filtered = match compiled_pattern with
                   | None -> filenames
                   | Some re ->
                       List.filter (fun name ->
                         match Str.search_forward re name 0 with
                         | exception Not_found -> false
                         | _ -> true
                       ) filenames
                 in
                 let sorted = List.sort String.compare filtered in
                 VList (List.map (fun name -> (None, VString name)) sorted)
               with Sys_error msg ->
                 Error.make_error FileError (Printf.sprintf "list_files: %s" msg)))
    ))
    env
  in
  (*
  --# Get environment variable
  --#
  --# Retrieves the value of an environment variable.
  --#
  --# @name env
  --# @param name :: String The name of the environment variable.
  --# @return :: String | Null The value of the variable, or null if not set.
  --# @example
  --#   env("HOME")
  --# @family core
  --# @export
  *)
  let env = Env.add "env"
    (make_builtin_named ~name:"env" 1 (fun args _env ->
      match args with
      | [(_, VString name)] | [(_, VSymbol name)] ->
          (match Sys.getenv_opt name with
           | Some value -> VString value
           | None -> VNull)
      | [(_, other)] ->
          Error.type_error (Printf.sprintf "Function `env` expects a String, got %s." (Utils.type_name other))
      | _ -> Error.arity_error_named "env" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  env
