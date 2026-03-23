(* src/package_manager/package_loader.ml *)
(* Runtime discovery and loading of external T packages.
   Decoupled from Eval to avoid dependency cycles: callers pass
   eval_program as a function parameter. *)

module String_set = Set.Make (String)

let ordered_unique_strings names =
  let (_seen, rev_names) =
    List.fold_left (fun (seen, acc) name ->
      if String_set.mem name seen then
        (seen, acc)
      else
        (String_set.add name seen, name :: acc)
    ) (String_set.empty, []) names
  in
  List.rev rev_names

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
    else
      let src_local = Filename.concat "src/packages" name in
      if Sys.file_exists src_local && Sys.is_directory src_local then Some src_local
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

(** Collect top-level names defined by a program, excluding internal metadata
    bindings reserved by the runtime. *)
let defined_names_in_program (program : Ast.program) : string list =
  List.filter_map (fun stmt ->
    match stmt.Ast.node with
    | Ast.Assignment { name; _ }
    | Ast.Reassignment { name; _ } when not (Import_registry.is_internal_key name) ->
        Some name
    | _ -> None
  ) program
  |> ordered_unique_strings

(** Package files should be able to define names that already exist in the
    caller environment (for example `mean` from a user package versus the
    builtin `mean`). Before evaluating a source file, temporarily remove any
    top-level names that came from the caller's original environment so `=`
    behaves like a fresh package-local definition. *)
let package_eval_env
    (base_env : Ast.environment)
    (current_env : Ast.environment)
    (program_names : string list) : Ast.environment =
  List.fold_left (fun acc name ->
    if Ast.Env.mem name base_env then Ast.Env.remove name acc else acc
  ) current_env program_names

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
        let eval_env = package_eval_env base_env env program_names in
        let (_v, new_env) = do_eval_program program eval_env in
        let updated_names = ordered_unique_strings (names @ program_names) in
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
  let defined_name_set =
    List.fold_left (fun acc name -> String_set.add name acc) String_set.empty defined_names
  in
  let extra_names =
    Ast.Env.fold (fun name _ acc ->
      if Import_registry.is_internal_key name
         || String_set.mem name defined_name_set
         || Ast.Env.mem name base_env then
        acc
      else
        name :: acc
    ) pkg_env []
    |> List.rev
  in
  let names = defined_names @ extra_names in
  List.filter_map (fun name ->
    match Ast.Env.find_opt name pkg_env with
    | Some value -> Some (name, value)
    | None -> None
  ) names

(** Build the standard package-prefixed binding name used for conflicts. *)
let prefixed_name package_name binding_name =
  package_name ^ "_" ^ binding_name

(** Generate a package-prefixed binding name that is unique in the current
    environment. If the preferred prefixed name is already owned by the same
    package, reuse it; otherwise append a numeric suffix until it is free. *)
let unique_prefixed_name env package_name binding_name =
  let base_name = prefixed_name package_name binding_name in
  let rec loop suffix =
    let candidate =
      if suffix = 0 then base_name
      else base_name ^ "_" ^ string_of_int suffix
    in
    match Import_registry.find_origin env candidate with
    | None when not (Ast.Env.mem candidate env) -> candidate
    | Some (Import_registry.ImportedPackage existing_pkg) when existing_pkg = package_name ->
        candidate
    | _ ->
        loop (suffix + 1)
  in
  loop 0

(** Add an imported binding to the environment and record which package owns
    that binding for future conflict resolution. *)
let add_imported_binding env target_name value package_name =
  let env = Ast.Env.add target_name value env in
  Import_registry.set_origin env target_name (Import_registry.ImportedPackage package_name)

(** Resolve import-name conflicts according to the package-loading rules:
    builtin names stay unchanged and conflicting package bindings are prefixed,
    while conflicts between two imported user packages rename both sides to
    package-prefixed names. *)
let resolve_binding_conflict
    ~(package_name : string)
    ~(binding_name : string)
    (value : Ast.value)
    (env : Ast.environment) : Ast.environment =
  let package_prefixed_name = unique_prefixed_name env package_name binding_name in
  match Import_registry.find_origin env binding_name with
  | None -> (
      match Import_registry.find_origin env package_prefixed_name with
      | Some (Import_registry.ImportedPackage existing_pkg) when existing_pkg = package_name ->
          add_imported_binding env package_prefixed_name value package_name
      | _ ->
          if Ast.Env.mem binding_name env then
            add_imported_binding env package_prefixed_name value package_name
          else
            add_imported_binding env binding_name value package_name)
  | Some (Import_registry.ImportedPackage existing_pkg) when existing_pkg = package_name ->
      add_imported_binding env binding_name value package_name
  | Some (Import_registry.ImportedPackage existing_pkg) ->
      let env =
        match Ast.Env.find_opt binding_name env with
        | Some existing_value ->
            let env = Ast.Env.remove binding_name env in
            let env = Import_registry.remove_origin env binding_name in
            let existing_prefixed_name = unique_prefixed_name env existing_pkg binding_name in
            add_imported_binding env existing_prefixed_name existing_value existing_pkg
        | None -> env
      in
      add_imported_binding env package_prefixed_name value package_name
  | Some Import_registry.Builtin ->
      if Ast.Env.mem binding_name env then
        add_imported_binding env package_prefixed_name value package_name
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
