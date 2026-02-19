(* src/package_manager/package_loader.ml *)
(* Runtime discovery and loading of external T packages.
   Decoupled from Eval to avoid dependency cycles: callers pass
   eval_program as a function parameter. *)

(** Search for a package directory by name.
    Checks T_PACKAGE_PATH (colon-separated dirs) then ./packages/<name>/ *)
let find_package (name : string) : string option =
  let check_dir dir =
    let candidate = Filename.concat dir name in
    if Sys.file_exists candidate && Sys.is_directory candidate then Some candidate
    else None
  in
  let from_env =
    try
      let path = Sys.getenv "T_PACKAGE_PATH" in
      let dirs = String.split_on_char ':' path in
      List.fold_left (fun acc dir ->
        match acc with
        | Some _ -> acc
        | None -> check_dir dir
      ) None dirs
    with Not_found -> None
  in
  match from_env with
  | Some _ -> from_env
  | None ->
    let local = Filename.concat "packages" name in
    if Sys.file_exists local && Sys.is_directory local then Some local
    else None

(** Collect all .t source files from a package's src/ directory, sorted. *)
let package_source_files (pkg_dir : string) : string list =
  let src_dir = Filename.concat pkg_dir "src" in
  if Sys.file_exists src_dir && Sys.is_directory src_dir then begin
    let entries = Sys.readdir src_dir in
    Array.sort String.compare entries;
    Array.to_list entries
    |> List.filter (fun e -> Filename.check_suffix e ".t")
    |> List.map (fun e -> Filename.concat src_dir e)
  end else
    []

(** Load a package's private-name set from its docs.json.
    Returns the list of function names tagged @private (is_export = false). *)
let load_private_names (pkg_dir : string) : string list =
  let docs_path = Filename.concat pkg_dir "help/docs.json" in
  if Sys.file_exists docs_path then begin
    try
      Tdoc_registry.load_from_json docs_path;
      let all_docs = Tdoc_registry.get_all () in
      let privates = List.filter_map (fun (entry : Tdoc_types.doc_entry) ->
        if not entry.is_export then Some entry.name else None
      ) all_docs in
      privates
    with _ -> []
  end else
    []

(** Evaluate all .t source files in a package directory.
    [do_eval_program] is injected by the caller to avoid a dependency on Eval. *)
let eval_package_sources
    ~(do_eval_program : Ast.program -> Ast.environment -> Ast.value * Ast.environment)
    (pkg_dir : string)
    (base_env : Ast.environment)
    : (Ast.environment, string) result =
  let files = package_source_files pkg_dir in
  if files = [] then
    Error (Printf.sprintf "Package directory '%s' has no source files in src/" pkg_dir)
  else
    try
      let pkg_env = List.fold_left (fun env file ->
        let ch = open_in file in
        let content = really_input_string ch (in_channel_length ch) in
        close_in ch;
        let lexbuf = Lexing.from_string content in
        let program = Parser.program Lexer.token lexbuf in
        let (_v, new_env) = do_eval_program program env in
        new_env
      ) base_env files in
      Ok pkg_env
    with
    | Lexer.SyntaxError msg ->
        Error (Printf.sprintf "Package '%s' syntax error: %s" (Filename.basename pkg_dir) msg)
    | Parser.Error ->
        Error (Printf.sprintf "Package '%s' parse error" (Filename.basename pkg_dir))
    | Sys_error msg ->
        Error (Printf.sprintf "Package '%s' file error: %s" (Filename.basename pkg_dir) msg)

(** Compute the set of new bindings introduced by a package env compared to a base env. *)
let new_bindings (base_env : Ast.environment) (pkg_env : Ast.environment)
    : (string * Ast.value) list =
  Ast.Env.fold (fun name value acc ->
    if Ast.Env.mem name base_env then acc
    else (name, value) :: acc
  ) pkg_env []

(** Load a package and import all public names into the caller's env. *)
let load_package
    ~(do_eval_program : Ast.program -> Ast.environment -> Ast.value * Ast.environment)
    (name : string) (env : Ast.environment)
    : (Ast.environment, string) result =
  match find_package name with
  | None ->
    Error (Printf.sprintf "Package '%s' not found. Check T_PACKAGE_PATH or install with 'nix develop'." name)
  | Some pkg_dir ->
    match eval_package_sources ~do_eval_program pkg_dir env with
    | Error msg -> Error msg
    | Ok pkg_env ->
      let private_names = load_private_names pkg_dir in
      let bindings = new_bindings env pkg_env in
      let public_bindings = List.filter (fun (n, _) ->
        not (List.mem n private_names)
      ) bindings in
      let new_env = List.fold_left (fun acc (n, v) ->
        Ast.Env.add n v acc
      ) env public_bindings in
      Ok new_env

(** Load a package and import only the specified names (with optional aliases). *)
let load_package_selective
    ~(do_eval_program : Ast.program -> Ast.environment -> Ast.value * Ast.environment)
    (name : string) (specs : Ast.import_spec list)
    (env : Ast.environment) : (Ast.environment, string) result =
  match find_package name with
  | None ->
    Error (Printf.sprintf "Package '%s' not found. Check T_PACKAGE_PATH or install with 'nix develop'." name)
  | Some pkg_dir ->
    match eval_package_sources ~do_eval_program pkg_dir env with
    | Error msg -> Error msg
    | Ok pkg_env ->
      let private_names = load_private_names pkg_dir in
      let bindings = new_bindings env pkg_env in
      List.fold_left (fun acc (spec : Ast.import_spec) ->
        match acc with
        | Error _ -> acc
        | Ok current_env ->
          if List.mem spec.import_name private_names then
            Error (Printf.sprintf "Cannot import '%s' from '%s': it is private." spec.import_name name)
          else
            match List.assoc_opt spec.import_name bindings with
            | None ->
              Error (Printf.sprintf "Name '%s' not found in package '%s'." spec.import_name name)
            | Some value ->
              let target_name = match spec.import_alias with
                | Some alias -> alias
                | None -> spec.import_name
              in
              Ok (Ast.Env.add target_name value current_env)
      ) (Ok env) specs
