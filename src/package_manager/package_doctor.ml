(* src/package_manager/package_doctor.ml *)
(* Implementation of `t doctor` for package validation *)

type issue_level = Error | Warning | Suggestion

type issue = {
  level : issue_level;
  message : string;
  suggestion : string option;
}

type static_node_requirements = {
  node_name : string;
  runtime : string;
  command : Ast.expr;
  serializer : Ast.expr;
  deserializer : Ast.expr;
}

(** Check if a file exists, returning an issue if it doesn't.
    
    @param path The file path to verify.
    @param description Brief description of the file. *)
let check_file_exists path description =
  if not (Sys.file_exists path) then
    Some {
      level = Error;
      message = Printf.sprintf "Missing %s: %s" description path;
      suggestion = Some (Printf.sprintf "Create %s" path);
    }
  else None

(** Check if a directory exists, returning an issue if it doesn't or if it is a file.
    
    @param path The directory path to verify.
    @param description Brief description of the directory. *)
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

(** Check if any files in a directory match a suffix pattern.
    
    @param dir The directory path to scan.
    @param pattern Suffix string to match.
    @param description Brief description of the expected files. *)
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

(** Validate package structure and recommend typical file components.
    
    @param dir The root directory of the package.
    @return A list of identified issues. *)
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

(** Validate project directory structure.
    
    @param dir The root directory of the project.
    @return A list of identified issues. *)
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


(** Check if Julia binary is installed on the system.
    
    @return [Some issue] if missing, [None] otherwise. *)
let check_julia_binary () =
  let code = Sys.command "command -v julia >/dev/null 2>&1" in
  if code <> 0 then
    Some {
      level = Warning;
      message = "Julia binary is not installed or not in PATH";
      suggestion = Some "Install Julia and ensure `julia` is available on PATH";
    }
  else None

(** Check if the installed Julia version satisfies T-Lang requirements (>= 1.6).
    
    @return [Some issue] if version is out of range or unparseable, otherwise [None]. *)
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
          match List.rev (List.filter (fun token -> String.trim token <> "") (String.split_on_char ' ' line)) with
          | v :: _ -> v
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

(** Verify if the JULIA_LOAD_PATH environment variable is configured correctly.
    
    @return [Some issue] if unconfigured, otherwise [None]. *)
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

(** Scan for required Julia packages (JSON, DataFrames, CSV, Arrow) in the environment.
    
    @return List of issues for missing packages. *)
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
          suggestion =
            Some
              (Printf.sprintf
                 "Add `%s` to `[jl-dependencies].packages` in `tproject.toml`, run `t update`, and re-enter `nix develop`."
                 pkg);
        }
    ) required_packages

let expr_string_value expr =
  match expr.Ast.node with
  | Ast.Value (Ast.VString s | Ast.VSymbol s) -> Some s
  | Ast.Var s -> Some s
  | _ -> None

let lookup_named_arg name args =
  List.assoc_opt (Some name) args

let lookup_dict_string keys expr =
  let rec go = function
    | [] -> None
    | key :: rest ->
        (match expr.Ast.node with
         | Ast.DictLit pairs ->
             (match List.assoc_opt key pairs with
              | Some value ->
                  (match expr_string_value value with
                   | Some _ as found -> found
                   | None -> go rest)
              | None -> go rest)
         | _ -> None)
  in
  go keys

let default_runtime_for_constructor = function
  | "pyn" -> "Python"
  | "rn" -> "R"
  | "jln" -> "Julia"
  | "qn" -> "Quarto"
  | "shn" -> "sh"
  | _ -> "T"

let runtime_from_path default_runtime path =
  match Filename.extension path with
  | ".R" -> "R"
  | ".py" -> "Python"
  | ".jl" -> "Julia"
  | ".qmd" -> "Quarto"
  | ".sh" -> "sh"
  | _ -> default_runtime

let default_serializer_expr runtime has_stdout_capture =
  if has_stdout_capture || runtime = "sh" then Ast.mk_expr (Ast.Var "text")
  else Ast.mk_expr (Ast.Var "default")

let read_script_expr ~project_root path =
  let full_path =
    if Filename.is_relative path then Filename.concat project_root path else path
  in
  try
    let ch = open_in full_path in
    let raw_text =
      Fun.protect
        ~finally:(fun () -> close_in_noerr ch)
        (fun () -> really_input_string ch (in_channel_length ch))
    in
    Ast.mk_expr
      (Ast.RawCode { raw_text; raw_identifiers = Ast.extract_identifiers raw_text })
  with Sys_error _ ->
    Ast.mk_expr (Ast.Value (Ast.VNA Ast.NAGeneric))

let static_requirements_of_node_expr ~project_root node_name expr =
  match expr.Ast.node with
  | Ast.Call { fn = { Ast.node = Ast.Var ("node" | "pyn" | "rn" | "jln" | "qn" | "shn" as constructor); _ }; args } ->
      let default_runtime = default_runtime_for_constructor constructor in
      let explicit_script_path = Option.bind (lookup_named_arg "script" args) expr_string_value in
      let command = match lookup_named_arg "command" args with
        | Some command -> command
        | None ->
            let arg_path =
              match lookup_named_arg "args" args with
              | Some dict_expr -> lookup_dict_string [ "path"; "file"; "qmd_file"; "input" ] dict_expr
              | None -> None
            in
            (match explicit_script_path with
             | Some path -> read_script_expr ~project_root path
             | None ->
                 (match arg_path with
                  | Some path -> read_script_expr ~project_root path
                  | None -> Ast.mk_expr (Ast.Value (Ast.VNA Ast.NAGeneric))))
      in
      let runtime =
        match Option.bind (lookup_named_arg "runtime" args) expr_string_value with
        | Some runtime when String.trim runtime <> "" -> runtime
        | _ ->
            (match explicit_script_path with
             | Some path -> runtime_from_path default_runtime path
             | None ->
                 let arg_path =
                   match lookup_named_arg "args" args with
                   | Some dict_expr -> lookup_dict_string [ "path"; "file"; "qmd_file"; "input" ] dict_expr
                   | None -> None
                 in
                 match arg_path with
                 | Some path when lookup_named_arg "command" args = None -> runtime_from_path default_runtime path
                 | _ -> default_runtime)
      in
      let has_stdout_capture =
        match lookup_named_arg "capture" args with
        | Some capture_expr ->
            (match expr_string_value capture_expr with
             | Some "stdout" -> true
             | _ -> false)
        | None -> false
      in
      let default_serializer = default_serializer_expr runtime has_stdout_capture in
      let serializer =
        match lookup_named_arg "serializer" args with
        | Some serializer -> serializer
        | None -> default_serializer
      in
      let deserializer =
        match lookup_named_arg "deserializer" args with
        | Some deserializer -> deserializer
        | None -> default_serializer
      in
      {
        node_name;
        runtime;
        command;
        serializer;
        deserializer;
      }
  | _ ->
      {
        node_name;
        runtime = "T";
        command = expr;
        serializer = Ast.mk_expr (Ast.Var "default");
        deserializer = Ast.mk_expr (Ast.Var "default");
      }

let rec pipeline_defs_in_expr expr =
  match expr.Ast.node with
  | Ast.PipelineDef nodes -> [nodes]
  | Ast.PipelineOfDef nodes ->
      List.concat (List.map (fun (_, e) -> pipeline_defs_in_expr e) nodes)
  | Ast.Call { fn; args } ->
      pipeline_defs_in_expr fn
      @ List.concat (List.map (fun (_, arg) -> pipeline_defs_in_expr arg) args)
  | Ast.IfElse { cond; then_; else_ } ->
      pipeline_defs_in_expr cond
      @ pipeline_defs_in_expr then_
      @ pipeline_defs_in_expr else_
  | Ast.Match { scrutinee; cases } ->
      pipeline_defs_in_expr scrutinee
      @ List.concat (List.map (fun (_, body) -> pipeline_defs_in_expr body) cases)
  | Ast.ListLit items ->
      List.concat (List.map (fun (_, item) -> pipeline_defs_in_expr item) items)
  | Ast.DictLit pairs ->
      List.concat (List.map (fun (_, item) -> pipeline_defs_in_expr item) pairs)
  | Ast.BinOp { left; right; _ }
  | Ast.BroadcastOp { left; right; _ } ->
      pipeline_defs_in_expr left @ pipeline_defs_in_expr right
  | Ast.UnOp { operand; _ }
  | Ast.DotAccess { target = operand; _ }
  | Ast.Unquote operand
  | Ast.UnquoteSplice operand
  | Ast.Lambda { body = operand; _ } ->
      pipeline_defs_in_expr operand
  | Ast.ListComp { expr; clauses } ->
      pipeline_defs_in_expr expr
      @ List.concat
          (List.map
             (function
               | Ast.CFor { iter; _ }
               | Ast.CFilter iter -> pipeline_defs_in_expr iter)
             clauses)
  | Ast.Block stmts ->
      pipeline_defs_in_program stmts
  | Ast.Value _
  | Ast.Var _
  | Ast.ColumnRef _
  | Ast.RawCode _
  | Ast.IntentDef _
  | Ast.ShellExpr _ -> []

and pipeline_defs_in_program program =
  List.concat
    (List.map
       (fun stmt ->
         match stmt.Ast.node with
         | Ast.Expression expr
         | Ast.Assignment { expr; _ }
         | Ast.Reassignment { expr; _ } -> pipeline_defs_in_expr expr
         | Ast.Import _
         | Ast.ImportPackage _
         | Ast.ImportFrom _
         | Ast.ImportFileFrom _ -> [])
       program)

let static_pipeline_for_doctor ~project_root nodes =
  let requirements =
    List.map (fun (node_name, expr) -> static_requirements_of_node_expr ~project_root node_name expr) nodes
  in
  {
    Ast.p_nodes = [];
    p_exprs = List.map (fun req -> (req.node_name, req.command)) requirements;
    p_deps = [];
    p_imports = [];
    p_runtimes = List.map (fun req -> (req.node_name, req.runtime)) requirements;
    p_serializers = List.map (fun req -> (req.node_name, req.serializer)) requirements;
    p_deserializers = List.map (fun req -> (req.node_name, req.deserializer)) requirements;
    p_env_vars = [];
    p_args = [];
    p_shells = [];
    p_shell_args = [];
    p_functions = [];
    p_includes = [];
    p_noops = [];
    p_scripts = [];
    p_explicit_deps = [];
    p_node_diagnostics = [];
  }

let read_file path =
  try
    let ch = open_in path in
    let content =
      Fun.protect
        ~finally:(fun () -> close_in_noerr ch)
        (fun () -> really_input_string ch (in_channel_length ch))
    in
    Result.ok content
  with Sys_error msg -> Result.error msg

let parse_program path =
  match read_file path with
  | Error msg -> Result.error (Printf.sprintf "Could not read %s: %s" path msg)
  | Ok content ->
      let lexbuf = Lexing.from_string content in
      lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = path };
      try Result.ok (Parser.program Lexer.token lexbuf)
      with
      | Lexer.SyntaxError msg -> Result.error (Printf.sprintf "Could not parse %s: %s" path msg)
      | Parser.Error -> Result.error (Printf.sprintf "Could not parse %s" path)

let doctor_issue_for_package ~section ~runtime pkg =
  {
    level = Warning;
    message = Printf.sprintf "Missing %s package `%s` in `tproject.toml`" runtime pkg;
    suggestion =
      Some
        (Printf.sprintf
           "Add `%s` to `%s.packages` in `tproject.toml`, run `t update`, and re-enter `nix develop`."
           pkg section);
  }

let canonical_pipeline_path dir =
  Filename.concat (Filename.concat dir "src") "pipeline.t"

let missing_pipeline_entrypoint_issue path =
  {
    level = Warning;
    message = Printf.sprintf "No pipeline entrypoint found at `%s`" path;
    suggestion =
      Some
        "Create `src/pipeline.t` to enable project pipeline dependency analysis in `t doctor`.";
  }

let has_declared_runtime_dependencies cfg =
  cfg.Package_types.proj_r_dependencies <> []
  || cfg.proj_py_dependencies <> []
  || cfg.proj_julia_dependencies <> []

let project_dependency_issues dir =
  let tproject_path = Filename.concat dir "tproject.toml" in
  let pipeline_path = canonical_pipeline_path dir in
  if not (Sys.file_exists tproject_path) then []
  else
    match read_file tproject_path with
    | Error _ -> []
    | Ok content ->
        (match Toml_parser.parse_tproject_toml content with
         | Error _ -> []
         | Ok cfg when not (Sys.file_exists pipeline_path) ->
             if has_declared_runtime_dependencies cfg then
              [missing_pipeline_entrypoint_issue pipeline_path]
             else []
         | Ok cfg ->
             match parse_program pipeline_path with
             | Error _ -> []
             | Ok program ->
                 match pipeline_defs_in_program program with
                 | [] -> []
                 | pipelines ->
                     let pipeline =
                       static_pipeline_for_doctor ~project_root:dir (List.concat pipelines)
                     in
                     let analysis =
                       Pipeline_dependency_requirements.analyze_missing_requirements pipeline cfg
                     in
                     List.concat [
                       List.map (doctor_issue_for_package ~section:"[r-dependencies]" ~runtime:"R") analysis.missing_r_deps;
                       List.map (doctor_issue_for_package ~section:"[py-dependencies]" ~runtime:"Python") analysis.missing_py_deps;
                       List.map (doctor_issue_for_package ~section:"[jl-dependencies]" ~runtime:"Julia") analysis.missing_julia_deps;
                     ])

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
    base_issues
  in
  let issues = issues @ julia_issues @ project_dependency_issues dir in

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
