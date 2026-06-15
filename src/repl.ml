(* src/repl.ml *)
(* CLI and interactive REPL for the T language — 0.51.1 *)

let version = Version.version

(* --- Readline / History --- *)

let history_file =
  try Filename.concat (Sys.getenv "HOME") ".t_history"
  with Not_found -> ".t_history"

let max_history_length = 1000

let () =
  ignore (LNoise.history_set ~max_length:max_history_length);
  ignore (LNoise.history_load ~filename:history_file)

(* --- Parsing and Evaluation --- *)

let source_location ?file pos : Ast.source_location =
  {
    file;
    line = pos.Lexing.pos_lnum;
    column = max 1 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1);
  }

let make_located_error ?file code message pos =
  Ast.VError {
    code;
    message;
    context = [];
    location = Some (source_location ?file pos);
    na_count = 0;
  }

let interrupt_error () =
  Ast.VError {
    code = Ast.RuntimeError;
    message = "Interrupted.";
    context = [];
    location = None;
    na_count = 0;
  }

let parse_and_eval ?filename ?(failfast=false) mode env input =
  let lexbuf = Lexing.from_string input in
  (match filename with
   | Some file -> lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = file }
   | None -> ());
  try
    let program = Parser.program Lexer.token lexbuf in
    match Typecheck.validate_program ~mode program with
    | Error err -> (Ast.VError err, env)
    | Ok () -> Eval.eval_program ~resilient:(not failfast) program env
  with
  | Lexer.SyntaxError msg ->
      let pos = Lexing.lexeme_start_p lexbuf in
      (make_located_error ?file:filename Ast.SyntaxError ("Syntax Error: " ^ msg) pos, env)
  | Parser.Error ->
      let pos = Lexing.lexeme_start_p lexbuf in
      (make_located_error ?file:filename Ast.SyntaxError "Parse Error" pos, env)
  | Sys.Break ->
      (interrupt_error (), env)

let run_file ?failfast mode filename env =
  try
    let ch = open_in filename in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    parse_and_eval ~filename ?failfast mode env content
  with
  | Sys_error msg ->
      (Ast.VError {
         code = Ast.FileError;
         message = "File Error: " ^ msg;
         context = [];
         location = None;
         na_count = 0;
       }, env)

(* --- Pipeline Detection --- *)

(** Recursively check if an expression contains a call to build_pipeline *)
let rec expr_has_build_pipeline = function
  | { Ast.node = Ast.Call { fn = { Ast.node = Ast.Var "build_pipeline"; _ }; _ }; _ } -> true
  | { Ast.node = Ast.Call { fn = { Ast.node = Ast.Var "populate_pipeline"; _ }; _ }; _ } -> true
  | { Ast.node = Ast.Call { fn; args; _ }; _ } ->
      expr_has_build_pipeline fn ||
      List.exists (fun (_, e) -> expr_has_build_pipeline e) args
  | { Ast.node = Ast.BinOp { left; right; _ } | Ast.BroadcastOp { left; right; _ }; _ } ->
      expr_has_build_pipeline left || expr_has_build_pipeline right
  | { Ast.node = Ast.IfElse { cond; then_; else_ }; _ } ->
      expr_has_build_pipeline cond ||
      expr_has_build_pipeline then_ ||
      expr_has_build_pipeline else_
  | { Ast.node = Ast.Match { scrutinee; cases }; _ } ->
      expr_has_build_pipeline scrutinee ||
      List.exists (fun (_, body) -> expr_has_build_pipeline body) cases
  | { Ast.node = Ast.Lambda { body; _ }; _ } -> expr_has_build_pipeline body
  | { Ast.node = Ast.ListLit items; _ } -> List.exists (fun (_, e) -> expr_has_build_pipeline e) items
  | { Ast.node = Ast.DictLit pairs; _ } -> List.exists (fun (_, e) -> expr_has_build_pipeline e) pairs
  | { Ast.node = Ast.UnOp { operand; _ }; _ } -> expr_has_build_pipeline operand
  | { Ast.node = Ast.DotAccess { target; _ }; _ } -> expr_has_build_pipeline target
  | { Ast.node = Ast.Block stmts; _ } -> List.exists stmt_has_build_pipeline stmts
  | { Ast.node = Ast.PipelineDef _; _ }
  | { Ast.node = Ast.PipelineOfDef _; _ } -> true
  | { Ast.node = Ast.ListComp { expr; _ }; _ } -> expr_has_build_pipeline expr
  | { Ast.node = Ast.IntentDef pairs; _ } -> List.exists (fun (_, e) -> expr_has_build_pipeline e) pairs
  | _ -> false

and stmt_has_build_pipeline = function
  | { Ast.node = Ast.Expression e; _ } -> expr_has_build_pipeline e
  | { Ast.node = Ast.Assignment { expr; _ }; _ } -> expr_has_build_pipeline expr
  | { Ast.node = Ast.Reassignment { expr; _ }; _ } -> expr_has_build_pipeline expr
  | { Ast.node = Ast.Import _ | Ast.ImportPackage _ | Ast.ImportFrom _ | Ast.ImportFileFrom _; _ } -> false

let program_has_build_pipeline (program : Ast.program) =
  List.exists stmt_has_build_pipeline program

(* --- Multi-line Input Detection --- *)

(** Count unmatched opening brackets/parens/braces in a string *)
let count_open_delimiters s =
  let depth = ref 0 in
  let in_string = ref false in
  let string_char = ref '"' in
  let len = String.length s in
  let i = ref 0 in
  while !i < len do
    let c = s.[!i] in
    if !in_string then begin
      if c = '\\' && !i + 1 < len then
        i := !i + 1  (* Skip escaped character *)
      else if c = !string_char then
        in_string := false
    end else begin
      match c with
      | '"' | '\'' -> in_string := true; string_char := c
      | '(' | '[' | '{' -> incr depth
      | ')' | ']' | '}' -> decr depth
      | _ -> ()
    end;
    i := !i + 1
  done;
  !depth

(** Check if input appears to be an incomplete expression *)
let is_incomplete input =
  let trimmed = String.trim input in
  if trimmed = "" then false
  else
    (* Unclosed delimiters *)
    let open_count = count_open_delimiters trimmed in
    if open_count > 0 then true
    (* Trailing pipe operator: |> or ?|> *)
    else
      let len = String.length trimmed in
      (len >= 3 && String.sub trimmed (len - 3) 3 = "?|>") ||
      (len >= 2 && String.sub trimmed (len - 2) 2 = "|>")

(* --- Pretty-Printing for REPL --- *)

let color_reset = "\027[0m"
let color_bold = "\027[1m"
let color_red = "\027[31m"
let color_blue = "\027[34m"
let color_gray = "\027[90m"

(** Pretty-print a value for REPL display *)
let repl_display_value v =
  let maybe_package_info v =
    match v with
    | Ast.VDict pairs ->
        let lookup key = List.assoc_opt key pairs in
        (match lookup "name", lookup "description", lookup "functions" with
        | Some (Ast.VString name), Some (Ast.VString description), Some (Ast.VList fns) ->
            let fn_names = List.filter_map (function (_, Ast.VString s) -> Some s | _ -> None) fns in
            if List.length fn_names = List.length fns then Some (name, description, fn_names)
            else None
        | _ -> None)
    | _ -> None
  in
  match v with
  | Ast.(VNA NAGeneric) -> ()
  | Ast.VError { context; _ } ->
      Printf.printf "%s%s%s\n" color_red (Ast.Utils.value_to_string v) color_reset;
      if context <> [] then begin
        Printf.printf "%sContext:%s\n" color_gray color_reset;
        List.iter (fun (k, v) -> Printf.printf "  %s: %s\n" k (Ast.Utils.value_to_string v)) context
      end;
      flush stdout
  | Ast.VDataFrame _ | Ast.VPipeline _ ->
      print_endline (Pretty_print.pretty_print_value v);
      flush stdout;
      flush stderr
  | other ->
      (match maybe_package_info other with
      | Some (name, description, functions) ->
          Printf.printf "\n  %s%s%s\n\n  %s\n\n  %sFunctions (%d):%s\n"
            color_bold name color_reset description color_blue (List.length functions) color_reset;
          List.iter (fun fn_name -> Printf.printf "    - %s\n" fn_name) functions;
          print_newline ()
      | None -> print_endline (Pretty_print.pretty_print_value other));
      flush stdout;
      flush stderr

(* --- Magic Commands and Help --- *)

let handle_magic line env mode base_keys =
  let parts = String.split_on_char ' ' (String.sub line 1 (String.length line - 1)) |> List.filter (fun s -> s <> "") in
  match parts with
  | "time" :: expr_parts ->
      let expr_str = String.concat " " expr_parts in
      let start_time = Unix.gettimeofday () in
      let (result, new_env) = parse_and_eval ?failfast:None mode env expr_str in
      let end_time = Unix.gettimeofday () in
      repl_display_value result;
      Printf.printf "%sExecution time: %.4f seconds%s\n" color_gray (end_time -. start_time) color_reset;
      flush stdout;
      (new_env, true)
  | ["ls"] ->
      let files = Sys.readdir "." |> Array.to_list in
      List.iter (fun f -> Printf.printf "%s  " f) files;
      print_newline ();
      flush stdout;
      (env, true)
  | ["pwd"] ->
      Printf.printf "%s\n" (Sys.getcwd ());
      flush stdout;
      (env, true)
  | ["cd"; dir] ->
      (try Sys.chdir dir with Sys_error msg -> Printf.printf "Error: %s\n" msg);
      flush stdout;
      (env, true)
  | ["env"] ->
      Array.iter print_endline (Unix.environment ());
      flush stdout;
      (env, true)
  | ["history"] ->
      Printf.printf "Command history showing is not fully implemented yet.\n";
      flush stdout;
      (env, true)
  | ["objects"] | ["who"] ->
      let names = Ast.Env.fold (fun k _ acc -> 
        if not (Hashtbl.mem base_keys k) then k :: acc else acc
      ) env [] |> List.sort String.compare in
      Printf.printf "%sUser-defined objects (%d):%s\n" color_blue (List.length names) color_reset;
      List.iter (fun n -> Printf.printf "  %s\n" n) names;
      print_newline ();
      flush stdout;
      (env, true)
  | _ ->
      Printf.printf "Unknown magic command: %s\n" line;
      flush stdout;
      (env, true)

(* --- CLI Commands --- *)

let print_help () =
  Printf.printf "T language — version %s\n\n" version;
  Printf.printf "Usage: t <command> [arguments]\n\n";
  Printf.printf "Commands:\n";
  Printf.printf "  repl              Start the interactive REPL (default)\n";
  Printf.printf "  run <file.t>      Execute a T source file\n";
  Printf.printf "  run --expr <expr> Execute a T expression directly\n";
  Printf.printf "  debug <node>      Start a subshell to debug a pipeline node\n";
  Printf.printf "  --mode <m>        Type-check mode: repl or strict\n";
  Printf.printf "  --failfast        Stop execution on first error\n";
  Printf.printf "  explain <expr>    Explain a value or expression\n";
  Printf.printf "  init --package <n>  Create a new T package\n";
  Printf.printf "  init --project <n>  Create a new T project\n";
  Printf.printf "  export_artifacts <file.t> <archive>  Export a pipeline cache archive\n";
  Printf.printf "  import_artifacts <file.t> <archive>  Import a pipeline cache archive\n";
  Printf.printf "  test              Run tests in the current directory\n";
  Printf.printf "  update            Update dependencies and nixpkgs date from tproject.toml\n";
  Printf.printf "  upgrade           Upgrade T version and nixpkgs date to today's date\n";
  Printf.printf "  doctor            Check package health\n";
  Printf.printf "  docs              Open documentation\n";
  Printf.printf "  --help, -h        Show this help message\n";
  Printf.printf "  --version, -v     Show version\n";
  Printf.printf "\nREPL Power Features:\n";
  Printf.printf "  %%time <expr>      Time an expression\n";
  Printf.printf "  %%objects          List user-defined objects\n"

let print_version () =
  Printf.printf "T language version %s\n" version

let exit_with_error message =
  Printf.eprintf "Error: %s\n" message;
  exit 1

let ensure_file_path filename =
  match Cli_args.validate_path ~kind:Cli_args.File filename with
  | Ok () -> ()
  | Error msg -> exit_with_error msg

let parse_program_from_file filename =
  try
    let ch = open_in filename in
    let content =
      Fun.protect
        ~finally:(fun () -> close_in_noerr ch)
        (fun () -> really_input_string ch (in_channel_length ch))
    in
    let lexbuf = Lexing.from_string content in
    lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
    try
      Ok (Parser.program Lexer.token lexbuf)
    with
    | Lexer.SyntaxError msg ->
        let pos = Lexing.lexeme_start_p lexbuf in
        Error (make_located_error ~file:filename Ast.SyntaxError ("Syntax Error: " ^ msg) pos)
    | Parser.Error ->
        let pos = Lexing.lexeme_start_p lexbuf in
        Error (make_located_error ~file:filename Ast.SyntaxError "Parse Error" pos)
    | Sys.Break ->
        Error (interrupt_error ())
  with
  | Sys_error msg ->
      Error (Ast.VError {
        code = Ast.FileError;
        message = "File Error: " ^ msg;
        context = [];
        location = None;
        na_count = 0;
      })

let resolve_pipeline_from_program_result filename (program : Ast.program) result env =
  let result = !Ast.meta_pipeline_flatten_resolver result in
  match result with
  | Ast.VPipeline p -> Ok p
  | _ ->
      let pipeline_bindings =
        Pipeline_script.top_level_assigned_names program
        |> List.filter_map (fun name ->
          match Ast.Env.find_opt name env with
          | Some v ->
              (match !Ast.meta_pipeline_flatten_resolver v with
               | Ast.VPipeline p -> Some (name, p)
               | _ -> None)
          | None -> None)
      in
      match List.assoc_opt "p" pipeline_bindings, pipeline_bindings with
      | Some p, _ -> Ok p
      | None, [(_, p)] -> Ok p
      | None, [] ->
          Error
            (Printf.sprintf
               "No pipeline value was found in `%s`. Return a Pipeline value or bind it to `p` before calling this command."
               filename)
      | None, bindings ->
          Error
            (Printf.sprintf
               "Multiple pipeline bindings were found in `%s` (%s). Bind the desired pipeline to `p` before calling this command."
               filename (String.concat ", " (List.map fst bindings)))

let cmd_artifact_transfer action filename archive_path env =
  Packages.ensure_docs_loaded ();
  ensure_file_path filename;
  match parse_program_from_file filename with
  | Error err ->
      Printf.eprintf "%s" (Pretty_print.pretty_print_value err);
      exit 1
  | Ok program ->
      let (result, new_env) = run_file Typecheck.Strict filename env in
      match result with
      | Ast.VError _ ->
          Printf.eprintf "%s" (Pretty_print.pretty_print_value result);
          exit 1
      | _ ->
          (match resolve_pipeline_from_program_result filename program result new_env with
           | Error msg -> exit_with_error msg
           | Ok pipeline ->
               let transfer_result =
                 match action with
                 | `Export -> Builder_artifacts.export_artifacts (VPipeline pipeline) archive_path
                 | `Import -> Builder_artifacts.import_artifacts (VPipeline pipeline) archive_path
               in
               match transfer_result with
               | Ok message -> Printf.printf "%s\n" message
               | Error err ->
                   Printf.eprintf "%s\n"
                     (Pretty_print.pretty_print_value
                        (Ast.VError {
                          code = err.code;
                          message = err.message;
                          context = [];
                          location = None;
                          na_count = 0;
                        }));
                   exit 1)

let flush_warnings_to_out () =
  match Sys.getenv_opt "out" with
  | Some out_path ->
      let wrote = ref false in
      let write_warnings warnings =
        let warning_values = List.map (fun w -> (None, Ast.Utils.node_warning_to_value w)) warnings in
        let json = Serialization.value_to_yojson (Ast.VList warning_values) in
        let warnings_path = Filename.concat out_path "warnings" in
        (try
           let ch = open_out warnings_path in
           output_string ch (Yojson.Safe.to_string ~std:true json);
           close_out ch
         with _ -> ())
      in
      (* Try pipeline diagnostics first (last evaluated node) *)
      (match !Eval.last_evaluated_node_name with
       | Some node_name ->
           (match List.find_opt (fun (n, _) -> n = node_name) !Eval.last_node_diagnostics with
            | Some (_, diag) when diag.Ast.nd_warnings <> [] ->
                write_warnings diag.Ast.nd_warnings; wrote := true
            | _ -> ())
       | None -> ());
      (* Fall back to global warnings (emitted outside pipeline eval) *)
      if not !wrote then begin
        let global = List.rev !Eval.global_warnings in
        if global <> [] then begin
          write_warnings global;
          Eval.global_warnings := []
        end
      end
  | None -> ()

let cmd_run ?(unsafe=false) ?failfast mode filename env =
  Packages.ensure_docs_loaded ();
  ensure_file_path filename;
  if not unsafe then begin
    try
      let ch = open_in filename in
      let content = really_input_string ch (in_channel_length ch) in
      close_in ch;
      let lexbuf = Lexing.from_string content in
      (try
        let program = Parser.program Lexer.token lexbuf in
        if not (program_has_build_pipeline program) then begin
          Printf.eprintf "Error: non-interactive execution requires a pipeline.\n";
          Printf.eprintf "Use --unsafe to override.\n";
          exit 1
        end
      with _ -> ())
    with _ -> ()
  end;
  let (result, _env) = run_file ?failfast mode filename env in
  flush_warnings_to_out ();
  match result with
  | Ast.VError _ ->
      Printf.eprintf "%s" (Pretty_print.pretty_print_value result); exit 1
  | Ast.(VNA NAGeneric) -> ()
  | v -> print_string (Pretty_print.pretty_print_value v)

let cmd_run_background ?(unsafe=false) ?failfast mode filename env =
  let _ = unsafe in
  let pid = Unix.fork () in
  if pid = -1 then begin
    Printf.eprintf "fork failed\n"; exit 1
  end else if pid = 0 then begin
    let devnull = Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
    Unix.dup2 devnull Unix.stdout;
    Unix.dup2 devnull Unix.stderr;
    Unix.close devnull;
    Packages.ensure_docs_loaded ();
    ensure_file_path filename;
    let (result, _env) = run_file ?failfast mode filename env in
    match result with
    | Ast.VError _ -> exit 1
    | _ -> exit 0
  end else begin
    Printf.printf "Build started in background (PID: %d)\n" pid;
    flush stdout;
    exit 0
  end

let cmd_run_expr ?failfast mode expr env =
  Packages.ensure_docs_loaded ();
  let (result, _) = parse_and_eval ?failfast mode env expr in
  flush_warnings_to_out ();
  match result with
  | Ast.VError _ ->
      Printf.eprintf "%s" (Pretty_print.pretty_print_value result); exit 1
  | Ast.(VNA NAGeneric) -> ()
  | v -> print_string (Pretty_print.pretty_print_value v)

let cmd_debug ?(unsafe=false) ?failfast mode filename node_name env =
  let _ = unsafe in
  Packages.ensure_docs_loaded ();
  ensure_file_path filename;
  let (result, new_env) = run_file ?failfast mode filename env in
  match result with
  | Ast.VError _ ->
      Printf.eprintf "%s" (Pretty_print.pretty_print_value result); exit 1
  | _ ->
      let find_node_by_name node_name env =
        let bindings = Ast.Env.bindings env in
        let rec search_pipelines = function
          | [] -> None
          | (_, Ast.VPipeline p) :: rest ->
              (match List.find_opt (fun (name, _) -> name = node_name) p.p_nodes with
               | Some (_, node_val) ->
                   (match node_val with
                    | Ast.VComputedNode cn -> Some cn
                    | _ -> search_pipelines rest)
               | None -> search_pipelines rest)
          | _ :: rest -> search_pipelines rest
        in
        match Ast.Env.find_opt node_name env with
        | Some (Ast.VComputedNode cn) -> Some cn
        | _ -> search_pipelines bindings
      in
      (match find_node_by_name node_name new_env with
       | Some cn ->
           let debug_func =
             match Ast.Env.find_opt "debug_node" new_env with
             | Some (Ast.VBuiltin b) -> b.b_func
             | _ -> exit_with_error "Function `debug_node` not found in pipeline package."
           in
           let named_args = [(Some "node", Ast.VComputedNode cn)] in
           let env_ref = ref new_env in
           let _ = debug_func named_args env_ref in
           ()
       | None ->
           exit_with_error (Printf.sprintf "Could not find node `%s` in the pipeline defined in '%s'." node_name filename))

let cmd_init_package args =
  match Scaffold.parse_init_flags args with
  | Error _ when args = [] ->
      let opts = Scaffold.interactive_init "" in
      (match Scaffold.scaffold_package opts with
      | Ok () -> Printf.printf "Package initialized successfully.\n"
      | Error e -> Printf.eprintf "Error: %s\n" e; exit 1)
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
  | Ok opts ->
      let opts = if opts.interactive then Scaffold.interactive_init opts.target_name else opts in
      match Scaffold.scaffold_package opts with
      | Ok () -> Printf.printf "Package initialized successfully.\n"
      | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1

let cmd_init_project args =
  match Scaffold.parse_init_flags args with
  | Error _ when args = [] ->
      let opts = Scaffold.interactive_init ~placeholder:"my_project" "" in
      (match Scaffold.scaffold_project opts with
      | Ok () -> Printf.printf "Project initialized successfully.\n"
      | Error e -> Printf.eprintf "Error: %s\n" e; exit 1)
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
  | Ok opts ->
      let opts = if opts.interactive then Scaffold.interactive_init ~placeholder:"my_project" opts.target_name else opts in
      match Scaffold.scaffold_project opts with
      | Ok () -> Printf.printf "Project initialized successfully.\n"
      | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1

let cmd_explain ?failfast mode rest env =
  Packages.ensure_docs_loaded ();
  let expr_str = String.concat " " (List.filter (fun s -> s <> "--json") rest) in
  if expr_str = "" then (Printf.eprintf "Usage: t explain <expr>\n"; exit 1)
  else begin
    let (result, env') = parse_and_eval ?failfast mode env expr_str in
    let explain_expr = "explain(__explain_target__)" in
    let env'' = Ast.Env.add "__explain_target__" result env' in
    let (explain_result, _) = parse_and_eval ?failfast mode env'' explain_expr in
    print_string (Pretty_print.pretty_print_value explain_result)
  end

let cmd_test args =
  let cwd = Sys.getcwd () in
  let opts =
    match Cli_args.parse_test_args ~cwd args with
    | Ok opts -> opts
    | Error msg -> exit_with_error msg
  in
  (match Cli_args.validate_path ~kind:Cli_args.Directory opts.target_dir with
   | Ok () -> ()
   | Error msg -> exit_with_error msg);
  let suite_result = Test_discovery.run_suite ~verbose:opts.verbose opts.target_dir in
  if suite_result.failed > 0 then exit 1

let cmd_doctor () = Package_doctor.run_doctor ()

let cmd_publish () =
  let dir = Sys.getcwd () in
  let tag_and_push v =
    match Release_manager.validate_tests_pass () with
    | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
    | Ok () ->
        match Release_manager.create_git_tag v with
        | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
        | Ok tag ->
            match Release_manager.push_git_tag tag with
            | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
            | Ok () -> Printf.printf "Successfully published %s\n" tag
  in
  match Release_manager.get_package_version dir with
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
  | Ok v ->
      Printf.printf "Publishing v%s...\n" v;
      match Release_manager.validate_version_format v with
      | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
      | Ok () ->
          match Release_manager.validate_clean_git () with
          | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
          | Ok () ->
              match Release_manager.validate_git_remote () with
              | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
              | Ok () ->
                  (match Release_manager.validate_changelog dir v with
                   | Error msg -> Printf.eprintf "Warning: %s\n" msg
                   | Ok () -> ());
                  tag_and_push v

let cmd_docs () = Documentation_manager.open_docs (Sys.getcwd ())

let rec mkdir_p path =
  if not (Sys.file_exists path) then begin
    let parent = Filename.dirname path in
    if parent <> path && parent <> "." && parent <> "/" then mkdir_p parent;
    (try Unix.mkdir path 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
  end

let recursive_files dir =
  let rec walk acc d =
    let entries = try Sys.readdir d with _ -> [||] in
    Array.fold_left (fun acc e ->
      let p = Filename.concat d e in
      if Sys.is_directory p then walk acc p
      else if Filename.check_suffix e ".ml" || Filename.check_suffix e ".t" then p :: acc
      else acc
    ) acc entries
  in walk [] dir

let cmd_doc args =
  let do_parse = List.mem "--parse" args || args = [] in
  let do_gen = List.mem "--generate" args || args = [] in
  let dir = Sys.getcwd () in
  let src_dir = Filename.concat dir "src" in
  if do_parse then begin
    List.iter (fun f -> List.iter Tdoc_registry.register (Tdoc_parser.parse_file f)) (recursive_files src_dir);
    let help_dir = Filename.concat dir "help" in
    mkdir_p help_dir;
    Tdoc_registry.to_json_file (Filename.concat help_dir "docs.json")
  end;
  if do_gen then begin
    let out_dir = Filename.concat dir "docs/reference" in
    mkdir_p out_dir;
    List.iter (fun e ->
      let ch = open_out (Filename.concat out_dir (e.Tdoc_types.name ^ ".md")) in
      output_string ch (Tdoc_markdown.generate_function_doc e); close_out ch
    ) (Tdoc_registry.get_all ())
  end

let cmd_update () =
  match Update_manager.update_flake_lock () with
  | Ok () -> Printf.printf "Updated.\n"
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1

let cmd_upgrade () =
  match Update_manager.cmd_upgrade () with
  | Ok () -> Printf.printf "Upgrade successful.\n"
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1

let get_nix_version () =
  try
    let ch = Unix.open_process_in "nix --version" in
    let line_result =
      try `Line (input_line ch)
      with
      | End_of_file -> `No_line
      | exn -> `Read_error exn
    in
    let close_result =
      try `Status (Unix.close_process_in ch)
      with exn -> `Close_error exn
    in
    match (line_result, close_result) with
    | (`Line line, `Status (Unix.WEXITED 0)) ->
        let parts = String.split_on_char ' ' line in
        let rec last = function [] -> "" | [x] -> x | _ :: xs -> last xs in
        last parts
    | (`Read_error exn, _) -> raise exn
    | _ -> "unknown"
  with _ -> "unknown"

(* --- Atelier TUI Variable Watcher Helper --- *)

let base_keys_ref = ref None

let write_vars_csv env =
  match Sys.getenv_opt "ATELIER_ACTIVE" with
  | Some "1" ->
      let root = Builder_utils.get_atelier_project_root () in
      Builder_utils.ensure_atelier_dir root;
      let tmp_path = Builder_utils.atelier_vars_tmp_path root in
      let final_path = Builder_utils.atelier_vars_path root in
      begin try
        let oc = open_out tmp_path in
        output_string oc "name,type,value\n";
        Ast.Env.iter (fun name value ->
          let should_show =
            match value with
            | Ast.VBuiltin _ -> false
            | Ast.VLambda _ -> false
            | _ ->
                if String.length name >= 2 && String.sub name 0 2 = "__" then false
                else
                  match !base_keys_ref with
                  | Some bk -> not (Hashtbl.mem bk name)
                  | None -> true
          in
          if should_show then begin
            let val_str = Ast.Utils.value_to_string value in
            let val_type =
              match value with
              | Ast.VInt _ -> "Int"
              | Ast.VFloat _ -> "Float"
              | Ast.VBool _ -> "Bool"
              | Ast.VString _ -> "String"
              | Ast.VDataFrame _ -> "DataFrame"
              | Ast.VList _ -> "List"
              | Ast.VDict _ -> "Dict"
              | Ast.VVector _ -> "Vector"
              | Ast.VNA _ -> "NA"
              | Ast.VError _ -> "Error"
              | Ast.VDate _ -> "Date"
              | Ast.VDatetime _ -> "Datetime"
              | Ast.VFactor _ -> "Factor"
              | Ast.VPeriod _ -> "Period"
              | Ast.VDuration _ -> "Duration"
              | Ast.VInterval _ -> "Interval"
              | Ast.VFormula _ -> "Formula"
              | Ast.VPipeline _ -> "Pipeline"
              | Ast.VMetaPipeline _ -> "MetaPipeline"
              | Ast.VComputedNode _ -> "ComputedNode"
              | Ast.VNode _ -> "Node"
              | Ast.VQuo _ -> "Quo"
              | Ast.VLambda _ -> "Lambda"
              | Ast.VBuiltin _ -> "Builtin"
              | Ast.VRawCode _ -> "RawCode"
              | Ast.VSymbol _ -> "Symbol"
              | Ast.VIntent _ -> "Intent"
              | _ -> "Unknown"
            in
            let escape s =
              let s = String.concat "\\n" (String.split_on_char '\n' s) in
              let escaped = String.concat "\"\"" (String.split_on_char '"' s) in
              "\"" ^ escaped ^ "\""
            in
            Printf.fprintf oc "%s,%s,%s\n" (escape name) (escape val_type) (escape val_str)
          end
        ) env;
        close_out oc;
        Sys.rename tmp_path final_path
      with _ ->
        begin try Sys.remove tmp_path with _ -> () end
      end
  | _ -> ()

let cmd_repl ?failfast mode env =
  Packages.ensure_docs_loaded ();
  
  (* Track base environment keys to filter %objects *)
  let base_keys = Hashtbl.create 200 in
  Ast.Env.iter (fun k _ -> Hashtbl.add base_keys k ()) env;
  base_keys_ref := Some base_keys;

  let nix_version = get_nix_version () in
  Printf.printf "T, a reproducibility-first orchestration engine for polyglot\n";
  Printf.printf "data science and statistical analysis.\n";
  Printf.printf "Version %s \"%s\" using Nix %s\n" version "Kaméhaméha" nix_version;
  Printf.printf "Licensed under the EUPL v1.2. No warranties.\n";
  Printf.printf "This software is in beta and is entirely LLM-generated — caveat emptor.\n";
  Printf.printf "Website: https://tstats-project.org\n";
  Printf.printf "Contributions are welcome!\n";
  Printf.printf "Type :quit or :q to exit, :help for commands.\n\n";
  Printf.printf "%s\n\n" (Import_registry.startup_rename_warning_message ());


  let scope = Symbol_table.create_scope () in
  Symbol_table.register_keywords scope;
  Symbol_table.populate_from_env scope env;

  LNoise.set_multiline true;
  LNoise.set_completion_callback (fun buffer completions ->
    let (start_pos, matches) = Completion.complete scope ~buffer ~cursor:(String.length buffer) in
    let prefix = String.sub buffer 0 start_pos in
    List.iter (fun m -> LNoise.add_completion completions (prefix ^ m)) matches
  );

  LNoise.set_hints_callback (fun buffer ->
    let cursor = String.length buffer in
    if cursor = 0 then None
    else
      let (start_pos, matches) = Completion.complete scope ~buffer ~cursor in
      match matches with
      | m :: _ ->
          let overlap = cursor - start_pos in
          if String.length m > overlap then
             let hint = String.sub m overlap (String.length m - overlap) in
             Some (hint, LNoise.White, false)
          else None
      | [] -> None
  );

  flush stdout;
  let is_tty = Unix.isatty Unix.stdin in
  let read_input prompt =
    if is_tty then LNoise.linenoise prompt
    else begin
      if prompt <> "" then Printf.printf "%s%!" prompt;
      try Some (input_line stdin) with End_of_file -> None
    end
  in

  let rec repl ?failfast env show_prompt =
    let prompt = if show_prompt then "T> " else "" in
    try
      match read_input prompt with
      | None ->
          if is_tty then print_endline "\nGoodbye."
      | Some line ->
          (* Handle TAB completion trigger for dumb terminals, but only if it's not part of valid code *)
          if String.contains line '\t' && String.trim line = "" then begin
            let tab_pos = String.index line '\t' in
            let prefix = String.sub line 0 tab_pos in
            let cursor = String.length prefix in
            let (_, matches) = Completion.complete scope ~buffer:prefix ~cursor in
            if matches = [] then
              Printf.printf "No completions.\n"
            else
              List.iter (fun m -> Printf.printf "%s\n" m) matches;
            flush stdout;
            repl env true
          end
          else
          let trimmed = String.trim line in
          if trimmed = "" then repl env true
          else begin
            if trimmed = ":quit" || trimmed = ":q" then
              print_endline "Exiting T REPL."
            else if trimmed = ":help" || trimmed = ":h" then begin
            Printf.printf "T language REPL commands:\n";
            Printf.printf "  :quit, :q     Exit the REPL\n";
            Printf.printf "  :help, :h     Show this help message\n";
            Printf.printf "  :version      Show T language and Nix versions\n";
            Printf.printf "  :packages     List all currently loaded packages\n\n";
            
            Printf.printf "Magic Commands:\n";
            Printf.printf "  %%time <expr>  Time an expression\n";
            Printf.printf "  %%ls           List directory contents\n";
            Printf.printf "  %%pwd          Print working directory\n";
            Printf.printf "  %%cd <dir>     Change directory\n";
            Printf.printf "  %%env          List environment variables\n";
            Printf.printf "  %%objects      List user-defined objects\n\n";
 
            Printf.printf "Resources:\n";
            Printf.printf "  Website:      https://tstats-project.org/\n";
            Printf.printf "  Bugs/Issues:  https://github.com/b-rodrigues/tlang/issues\n\n";
 
            Printf.printf "Multi-line input:\n";
            Printf.printf "  Expressions with unclosed (, [, { or trailing |> automatically continue on the next line.\n\n";
            flush stdout;
            repl env true
            end
            else if trimmed = ":version" then begin
            Printf.printf "T language version %s\n" version;
            flush stdout;
            repl env true
            end
            else if trimmed = ":packages" then begin
            List.iter (fun (pkg : Packages.package_info) ->
              Printf.printf "  %-12s  %s\n" pkg.name pkg.description
            ) Packages.all_packages;
            print_newline ();
            flush stdout;
            repl env true
            end
            else if String.length trimmed > 10 && String.sub trimmed 0 10 = ":complete " then begin
              let arg = String.trim (String.sub trimmed 10 (String.length trimmed - 10)) in
              let cursor = String.length arg in
              let (_start_pos, matches) = Completion.complete scope ~buffer:arg ~cursor in
              Printf.printf "\n:BEGIN_COMPLETIONS:\n";
              List.iter (fun m -> Printf.printf "%s\n" m) matches;
              Printf.printf ":END_COMPLETIONS:\n";
              flush stdout;
              repl env true
            end
            else if String.length trimmed > 0 && trimmed.[0] = '%' then begin
            let (new_env, handled) = handle_magic trimmed env mode base_keys in
            if handled then (
              write_vars_csv new_env;
              if is_tty then (
                ignore (LNoise.history_add line);
                ignore (LNoise.history_save ~filename:history_file)
              );
              repl new_env true
            ) else repl env true
            end
            else begin
            (* Multi-line input: accumulate lines while expression is incomplete *)
            let rec read_multiline acc =
              let combined = acc in
              if is_incomplete combined then begin
                try
                  match read_input ".. " with
                  | None ->
                      combined  (* Return what we have *)
                  | Some next_line ->
                      (* If the previous line ends with |> or ?|>, move it to the start of
                         the next line so the lexer recognizes the continuation *)
                      let trimmed_acc = String.trim combined in
                      let len = String.length trimmed_acc in
                      if len >= 3 && String.sub trimmed_acc (len - 3) 3 = "?|>" then
                        let prefix = String.sub combined 0 (String.length combined - 3) in
                        read_multiline (String.trim prefix ^ "\n  ?|> " ^ next_line)
                      else if len >= 2 && String.sub trimmed_acc (len - 2) 2 = "|>" then
                        let prefix = String.sub combined 0 (String.length combined - 2) in
                        read_multiline (String.trim prefix ^ "\n  |> " ^ next_line)
                      else
                        read_multiline (combined ^ "\n" ^ next_line)
                with
                | Sys.Break ->
                    raise Sys.Break
              end else
                combined
            in
            let full_input = read_multiline trimmed in
            if is_tty then (
              ignore (LNoise.history_add full_input);
              ignore (LNoise.history_save ~filename:history_file)
            );
            let (result, new_env) = parse_and_eval ?failfast mode env full_input in
            write_vars_csv new_env;
            Symbol_table.populate_from_env scope new_env;
            repl_display_value result;
            repl ?failfast new_env true
            end
          end
    with
    | Sys.Break ->
        print_endline "Interrupted.";
        repl ?failfast env true
  in
  repl ?failfast env true

(* --- Entry Point --- *)

let () =
  Sys.catch_break true;
  let raw_args = Array.to_list Sys.argv in
  let mode_parse =
    match Cli_args.parse_mode_args raw_args with
    | Ok parsed -> parsed
    | Error msg -> Printf.eprintf "%s\n" msg; exit 1
  in
  let unsafe = List.mem "--unsafe" raw_args in
  let failfast = mode_parse.failfast in
  let args = if unsafe then List.filter (fun s -> s <> "--unsafe") mode_parse.args else mode_parse.args in
  let args = if failfast then List.filter (fun s -> s <> "--failfast") args else args in
  (match Cli_args.validate_cli_flags ~mode_flag:mode_parse.mode_flag ~unsafe_flag:unsafe ~failfast_flag:failfast args with
   | Ok () -> ()
   | Error msg -> exit_with_error msg);
  let env = Packages.init_env () in
  (* Register interactive CLI wrappers — must be here (not in packages.ml)
     to avoid dependency cycles with Test_discovery *)
(*
--# Run a T script
--#
--# Evaluates a T script file and imports its definitions into the current environment.
--# Useful for interactive development to reload module files.
--#
--# @name t_run
--# @param filename :: String The path to the T file to execute.
--# @param failfast :: Bool Whether to fail on error (defaults to false).
--# @return :: Null
--# @example
--#   t_run("src/my_script.t")
--# @family repl
--# @export
*)
  let env = Ast.Env.add "t_run"
    (Ast.VBuiltin { b_name = Some "t_run"; b_arity = 1; b_variadic = false;
      b_func = (fun named_args env_ref ->
        let f_filename = ref None in
        let f_failfast = ref false in
        List.iter (fun (k, v) ->
          match k, v with
          | Some "filename", Ast.VString s -> f_filename := Some s
          | None, Ast.VString s -> f_filename := Some s
          | Some "failfast", Ast.VBool b -> f_failfast := b
          | _ -> ()
        ) named_args;
        match !f_filename with
        | Some filename ->
            (try
              let ch = open_in filename in
              let content = really_input_string ch (in_channel_length ch) in
              close_in ch;
              let lexbuf = Lexing.from_string content in
                (try
                 let program = Parser.program Lexer.token lexbuf in
                 let eval_env = Pipeline_script.reload_env_for_pipeline_entry ~filename program !env_ref in
                 let (v, new_env) = Eval.eval_program ~resilient:(not !f_failfast) program eval_env in
                 (match v with
                  | Ast.VError _ -> v
                  | _ ->
                     env_ref := Pipeline_script.remember_pipeline_entry_bindings ~filename program new_env;
                     Printf.printf "Ran %s successfully.\n" filename; flush stdout; Ast.(VNA NAGeneric))
               with
               | Lexer.SyntaxError msg ->
                   let pos = Lexing.lexeme_start_p lexbuf in
                   make_located_error ~file:filename Ast.SyntaxError ("Syntax error in '" ^ filename ^ "': " ^ msg) pos
               | Parser.Error ->
                   let pos = Lexing.lexeme_start_p lexbuf in
                   make_located_error ~file:filename Ast.SyntaxError (Printf.sprintf "Parse error in '%s'" filename) pos
               | Sys.Break ->
                   interrupt_error ())
             with
             | Sys_error msg ->
                 Ast.VError { code = Ast.FileError; message = Printf.sprintf "t_run failed: %s" msg; context = []; location = None; na_count = 0 })
        | _ -> Ast.VError { code = Ast.TypeError; message = "t_run expects a file path string."; context = []; location = None; na_count = 0 })
    })
    env
  in
  let env = Ast.Env.add "tui_update"
    (Ast.VBuiltin { b_name = Some "tui_update"; b_arity = 0; b_variadic = false;
      b_func = (fun _named_args env_ref ->
        write_vars_csv !env_ref;
        Ast.(VNA NAGeneric))
    })
    env
  in
(*
--# Build Pipeline Internally
--#
--# Builds the `src/pipeline.t` pipeline entrypoint.
--#
--# @name t_make
--# @param filename :: String (Optional) The pipeline build script path. Must be `src/pipeline.t`.
--# @family repl
--# @export
*)
  let env = T_make_mod.register env in
(*
--# Run tests
--#
--# Runs the test suite for the current package.
--# Wraps the CLI `t test` command for use within the REPL.
--#
--# @name t_test
--# @return :: NA Returns NA on success, or an Error if tests fail.
--# @family repl
--# @export
*)
  let env = Ast.Env.add "t_test"
    (Ast.VBuiltin { b_name = Some "t_test"; b_arity = 0; b_variadic = false;
      b_func = (fun _named_args _env_ref ->
        let dir = Sys.getcwd () in
        let suite_result = Test_discovery.run_suite ~verbose:false dir in
        if suite_result.failed > 0 then
          Ast.VError { code = Ast.GenericError; message = Printf.sprintf "%d test(s) failed." suite_result.failed; context = []; location = None; na_count = 0 }
        else begin
          Printf.printf "All %d test(s) passed.\n" suite_result.passed;
          flush stdout;
          Ast.(VNA NAGeneric)
        end)
    })
    env
  in
(*
--# Generate Documentation
--#
--# Documentation tools. Call with "parse" to extract docs from `src/`,
--# or "generate" to output markdown files to `docs/reference/`.
--#
--# @name t_doc
--# @param command :: String Either "parse" or "generate".
--# @return :: Null
--# @example
--#   t_doc("parse")
--#   t_doc("generate")
--# @family repl
--# @export
*)
  let env = Ast.Env.add "t_doc"
    (Ast.VBuiltin { b_name = Some "t_doc"; b_arity = 1; b_variadic = false;
      b_func = (fun named_args _env_ref ->
        match List.map snd named_args with
        | [Ast.VString "parse"] ->
            let dir = Sys.getcwd () in
            let src_dir = Filename.concat dir "src" in
            Printf.printf "Parsing documentation from %s...\n" src_dir;
            let files = recursive_files src_dir in
            List.iter (fun f ->
              let docs = Tdoc_parser.parse_file f in
              List.iter Tdoc_registry.register docs
            ) files;
            let help_dir = Filename.concat dir "help" in
            if not (Sys.file_exists help_dir) then Unix.mkdir help_dir 0o755;
            Tdoc_registry.to_json_file (Filename.concat help_dir "docs.json");
            Printf.printf "Parsed %d functions.\n" (List.length (Tdoc_registry.get_all ()));
            flush stdout;
            Ast.(VNA NAGeneric)
        | [Ast.VString "generate"] ->
            let dir = Sys.getcwd () in
            Printf.printf "Generating Markdown in docs/reference...\n";
            let ensure_dir path =
              if Sys.file_exists path then
                (if not (Sys.is_directory path) then
                  Error (Printf.sprintf "%s exists and is not a directory" path)
                else Ok ())
              else
                (try Unix.mkdir path 0o755; Ok () with Unix.Unix_error (e, _, _) -> Error (Unix.error_message e))
            in
            let docs_dir = Filename.concat dir "docs" in
            (match ensure_dir docs_dir with Error msg -> Ast.VError { code = Ast.FileError; message = msg; context = []; location = None; na_count = 0 } | Ok () ->
            let out_dir = Filename.concat docs_dir "reference" in
            (match ensure_dir out_dir with Error msg -> Ast.VError { code = Ast.FileError; message = msg; context = []; location = None; na_count = 0 } | Ok () ->
            let entries = Tdoc_registry.get_all () in
            List.iter (fun (e : Tdoc_types.doc_entry) ->
              if e.is_export then begin
                let content = Tdoc_markdown.generate_function_doc e in
                let path = Filename.concat out_dir (e.name ^ ".md") in
                let ch = open_out path in
                output_string ch content;
                close_out ch
              end
            ) entries;
            let index_content = Tdoc_markdown.generate_index entries in
            let ch = open_out (Filename.concat out_dir "index.md") in
            output_string ch index_content;
            close_out ch;
            Printf.printf "Documentation generated in %s\n" out_dir;
            flush stdout;
            Ast.(VNA NAGeneric)))
        | [Ast.VString other] ->
            Ast.VError { code = Ast.ValueError; message = Printf.sprintf "t_doc expects \"parse\" or \"generate\", got \"%s\"." other; context = []; location = None; na_count = 0 }
        | _ -> Ast.VError { code = Ast.TypeError; message = "t_doc expects a string argument: \"parse\" or \"generate\"."; context = []; location = None; na_count = 0 })
    })
    env
  in

  match args with
  | _ :: "debug" :: [] ->
      Printf.eprintf "Usage: t debug <node_name> | t debug <file.t> <node_name>\n";
      exit 1
  | _ :: "debug" :: node_name :: [] ->
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_debug ~unsafe ~failfast script_mode "src/pipeline.t" node_name env
  | _ :: "debug" :: filename :: node_name :: [] ->
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_debug ~unsafe ~failfast script_mode filename node_name env
  | _ :: "top" :: rest -> Cmd_top.cmd_top rest env
  | _ :: "run" :: [] ->
      Printf.eprintf "Usage: t run <file.t> | t run --expr <expr>\n";
      exit 1
  | _ :: "run" :: "--expr" :: [] ->
      Printf.eprintf "Missing expression after --expr.\n";
      exit 1
  | _ :: "run" :: "--expr" :: expr :: [] ->
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_run_expr ~failfast script_mode expr env
  | _ :: "run" :: "--expr" :: _ ->
      Printf.eprintf "Unexpected arguments after `t run --expr <expr>`.\n";
      exit 1
  | _ :: "run" :: "--background" :: filename :: [] ->
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_run_background ~unsafe ~failfast script_mode filename env
  | _ :: "run" :: filename :: [] ->
      (* Default to Strict mode for scripts, but allow --mode to override *)
      let script_mode = if mode_parse.mode = Typecheck.Repl && not mode_parse.mode_flag then Typecheck.Strict else mode_parse.mode in
      cmd_run ~unsafe ~failfast script_mode filename env
  | _ :: "run" :: _ ->
      Printf.eprintf "Unexpected arguments after `t run <file.t>`.\n";
      exit 1
  | _ :: "repl" :: _ -> cmd_repl ~failfast mode_parse.mode env
  | _ :: "explain" :: rest -> cmd_explain ~failfast mode_parse.mode rest env
  | _ :: "init" :: "--package" :: rest -> cmd_init_package rest
  | _ :: "init" :: "--project" :: rest -> cmd_init_project rest
  | _ :: "test" :: rest -> cmd_test rest
  | _ :: "doctor" :: _ -> cmd_doctor ()
  | _ :: "docs" :: _ -> cmd_docs ()
  | _ :: "doc" :: rest -> cmd_doc rest
  | _ :: "update" :: _ -> cmd_update ()
  | _ :: "upgrade" :: _ -> cmd_upgrade ()
  | _ :: "publish" :: _ -> cmd_publish ()
  | _ :: "export_artifacts" :: [filename; archive_path] ->
      cmd_artifact_transfer `Export filename archive_path env
  | _ :: "import_artifacts" :: [filename; archive_path] ->
      cmd_artifact_transfer `Import filename archive_path env

  | _ :: "init" :: _ ->
      Printf.eprintf "Usage: t init --package <name> | t init --project <name> [options]\n";
      Printf.eprintf "Run 't init --package --help' for more information.\n";
      exit 1
  | _ :: "export_artifacts" :: _ ->
      Printf.eprintf "Usage: t export_artifacts <pipeline.t> <archive_path>\n";
      exit 1
  | _ :: "import_artifacts" :: _ ->
      Printf.eprintf "Usage: t import_artifacts <pipeline.t> <archive_path>\n";
      exit 1
  | _ :: "--help" :: _ | _ :: "-h" :: _ -> print_help ()
  | _ :: "--version" :: _ | _ :: "-v" :: _ -> print_version ()
  | [_] ->
      (* No arguments: start the REPL (default behavior) *)
      cmd_repl ~failfast mode_parse.mode env
  | _ :: unknown :: _ ->
      Printf.eprintf "Unknown command: %s\n" unknown;
      Printf.eprintf "Run 't --help' for usage information.\n";
      exit 1
  | [] -> cmd_repl ~failfast mode_parse.mode env
