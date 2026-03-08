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

(** Collect top-level names defined by a program. *)
let defined_names_in_program (program : Ast.program) : string list =
  List.fold_left (fun acc stmt ->
    match stmt with
    | Ast.Assignment { name; _ }
    | Ast.Reassignment { name; _ } ->
        if List.mem name acc || name = Import_registry.metadata_key then acc
        else acc @ [name]
    | _ -> acc
  ) [] program

(** Evaluate all .t source files in a package directory.
    [do_eval_program] is injected by the caller to avoid a dependency on Eval. *)
let eval_package_sources
    ~(do_eval_program : Ast.program -> Ast.environment -> Ast.value * Ast.environment)
    (pkg_dir : string)
    (base_env : Ast.environment)
    : ((Ast.environment * string list), string) result =
  let files = package_source_files pkg_dir in
  if files = [] then
    Error (Printf.sprintf "Package directory '%s' has no valid src/ directory or it is empty" pkg_dir)
  else
    try
      let (pkg_env, defined_names) = List.fold_left (fun (env, names) file ->
        let ch = open_in file in
        let content = really_input_string ch (in_channel_length ch) in
        close_in ch;
        let lexbuf = Lexing.from_string content in
        let program = Parser.program Lexer.token lexbuf in
        let program_names = defined_names_in_program program in
        let (_v, new_env) = do_eval_program program env in
        let updated_names = List.fold_left (fun acc name ->
          if List.mem name acc then acc else acc @ [name]
        ) names program_names in
        (new_env, updated_names)
      ) (base_env, []) files in
      Ok (pkg_env, defined_names)
    with
    | Lexer.SyntaxError msg ->
        Error (Printf.sprintf "Package '%s' syntax error: %s" (Filename.basename pkg_dir) msg)
    | Parser.Error ->
        Error (Printf.sprintf "Package '%s' parse error" (Filename.basename pkg_dir))
    | Sys_error msg ->
        Error (Printf.sprintf "Package '%s' file error: %s" (Filename.basename pkg_dir) msg)

(** Compute the set of bindings defined or newly introduced by a package. *)
let package_bindings
    (base_env : Ast.environment)
    (defined_names : string list)
    (pkg_env : Ast.environment)
    : (string * Ast.value) list =
  let names =
    Ast.Env.fold (fun name _ acc ->
      if name = Import_registry.metadata_key || List.mem name acc then
        acc
      else if Ast.Env.mem name base_env || List.mem name defined_names then
        if List.mem name defined_names then acc @ [name] else acc
      else
        acc @ [name]
    ) pkg_env defined_names
  in
  List.filter_map (fun name ->
    match Ast.Env.find_opt name pkg_env with
    | Some value -> Some (name, value)
    | None -> None
  ) names

let prefixed_name package_name binding_name =
  package_name ^ "_" ^ binding_name

let add_imported_binding env target_name value package_name =
  let env = Ast.Env.add target_name value env in
  Import_registry.set_origin env target_name (Import_registry.ImportedPackage package_name)

let resolve_binding_conflict
    ~(package_name : string)
    ~(binding_name : string)
    (value : Ast.value)
    (env : Ast.environment) : Ast.environment =
  match Import_registry.find_origin env binding_name with
  | Some (Import_registry.ImportedPackage existing_pkg) when existing_pkg = package_name ->
      add_imported_binding env binding_name value package_name
  | Some (Import_registry.ImportedPackage existing_pkg) ->
      let env =
        match Ast.Env.find_opt binding_name env with
        | Some existing_value ->
            let env = Ast.Env.remove binding_name env in
            let env = Import_registry.remove_origin env binding_name in
            add_imported_binding env (prefixed_name existing_pkg binding_name) existing_value existing_pkg
        | None -> env
      in
      add_imported_binding env (prefixed_name package_name binding_name) value package_name
  | Some Import_registry.Builtin
  | None ->
      if Ast.Env.mem binding_name env then
        add_imported_binding env (prefixed_name package_name binding_name) value package_name
      else
        add_imported_binding env binding_name value package_name

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
    | Ok (pkg_env, defined_names) ->
      let private_names = load_private_names pkg_dir in
      let bindings = package_bindings env defined_names pkg_env in
      let public_bindings = List.filter (fun (n, _) ->
        not (List.mem n private_names)
      ) bindings in
      let new_env = List.fold_left (fun acc (n, v) ->
        resolve_binding_conflict ~package_name:name ~binding_name:n v acc
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
    | Ok (pkg_env, defined_names) ->
      let private_names = load_private_names pkg_dir in
      let bindings = package_bindings env defined_names pkg_env in
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
                if spec.import_alias = None then
                  Ok (resolve_binding_conflict ~package_name:name ~binding_name:target_name value current_env)
                else
                  Ok (Ast.Env.add target_name value current_env)
      ) (Ok env) specs
