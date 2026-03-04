open Ast

let register env =
  let env = Env.add "getwd"
    (make_builtin_named ~name:"getwd" 0 (fun _args _env ->
      VString (Sys.getcwd ())
    ))
    env
  in
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
  let env = Env.add "read_file"
    (make_builtin_named ~name:"read_file" 1 (fun args _env ->
      match args with
      | [(_, VString path)] | [(_, VSymbol path)] ->
          (try
            let ic = open_in path in
            Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
              let n = in_channel_length ic in
              let buf = Bytes.create n in
              really_input ic buf 0 n;
              VString (Bytes.to_string buf)
            )
          with Sys_error msg ->
            Error.make_error FileError (Printf.sprintf "read_file: %s" msg))
      | [(_, other)] ->
          Error.type_error (Printf.sprintf "Function `read_file` expects a String, got %s." (Utils.type_name other))
      | _ -> Error.arity_error_named "read_file" ~expected:1 ~received:(List.length args)
    ))
    env
  in
  let env = Env.add "list_files"
    (make_builtin_named ~name:"list_files" ~variadic:true 0 (fun args _env ->
      let positional = List.filter (fun (name, _) -> name = None) args in
      let path_result = match positional with
        | (_, VString s) :: _ -> Ok s
        | (_, VSymbol s) :: _ -> Ok s
        | (_, other) :: _ ->
            Error (Printf.sprintf "Function `list_files` expects a String path, got %s." (Utils.type_name other))
        | [] -> Ok "."
      in
      match path_result with
      | Error msg -> Error.type_error msg
      | Ok path ->
          let pattern = match List.assoc_opt (Some "pattern") args with
            | Some (VString s) -> Some s
            | Some (VSymbol s) -> Some s
            | _ -> None
          in
          (try
            let entries = Sys.readdir path in
            let filenames = Array.to_list entries in
            let filtered = match pattern with
              | None -> filenames
              | Some pat ->
                  let re = Str.regexp pat in
                  List.filter (fun name ->
                    match Str.search_forward re name 0 with
                    | exception Not_found -> false
                    | _ -> true
                  ) filenames
            in
            let sorted = List.sort String.compare filtered in
            VList (List.map (fun name -> (None, VString name)) sorted)
          with Sys_error msg ->
            Error.make_error FileError (Printf.sprintf "list_files: %s" msg))
    ))
    env
  in
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
