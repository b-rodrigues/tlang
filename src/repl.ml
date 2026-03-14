(* src/repl.ml *)
(* CLI and interactive REPL for the T language — Phase 7 Alpha *)

let version = "0.5.0-alpha"

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
  }

let interrupt_error () =
  Ast.VError {
    code = Ast.RuntimeError;
    message = "Interrupted.";
    context = [];
    location = None;
  }

let parse_and_eval ?filename mode env input =
  let lexbuf = Lexing.from_string input in
  (match filename with
   | Some file -> lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = file }
   | None -> ());
  try
    let program = Parser.program Lexer.token lexbuf in
    match Typecheck.validate_program ~mode program with
    | Error msg ->
        (Ast.VError {
           code = Ast.TypeError;
           message = msg;
           context = [];
           location = None;
         }, env)
    | Ok () -> Eval.eval_program program env
  with
  | Lexer.SyntaxError msg ->
      let pos = Lexing.lexeme_start_p lexbuf in
      (make_located_error ?file:filename Ast.SyntaxError ("Syntax Error: " ^ msg) pos, env)
  | Parser.Error ->
      let pos = Lexing.lexeme_start_p lexbuf in
      (make_located_error ?file:filename Ast.SyntaxError "Parse Error" pos, env)
  | Sys.Break ->
      (interrupt_error (), env)

let run_file mode filename env =
  try
    let ch = open_in filename in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    parse_and_eval ~filename mode env content
  with
  | Sys_error msg ->
      (Ast.VError {
         code = Ast.FileError;
         message = "File Error: " ^ msg;
         context = [];
         location = None;
       }, env)

(* --- Pipeline Detection --- *)

(** Recursively check if an expression contains a call to build_pipeline *)
let rec expr_has_build_pipeline = function
  | Ast.Call { fn = Ast.Var "build_pipeline"; _ } -> true
  | Ast.Call { fn = Ast.Var "populate_pipeline"; _ } -> true
  | Ast.Call { fn; args; _ } ->
      expr_has_build_pipeline fn ||
      List.exists (fun (_, e) -> expr_has_build_pipeline e) args
  | Ast.BinOp { left; right; _ } | Ast.BroadcastOp { left; right; _ } ->
      expr_has_build_pipeline left || expr_has_build_pipeline right
  | Ast.IfElse { cond; then_; else_ } ->
      expr_has_build_pipeline cond ||
      expr_has_build_pipeline then_ ||
      expr_has_build_pipeline else_
  | Ast.Lambda { body; _ } -> expr_has_build_pipeline body
  | Ast.ListLit items -> List.exists (fun (_, e) -> expr_has_build_pipeline e) items
  | Ast.DictLit pairs -> List.exists (fun (_, e) -> expr_has_build_pipeline e) pairs
  | Ast.UnOp { operand; _ } -> expr_has_build_pipeline operand
  | Ast.DotAccess { target; _ } -> expr_has_build_pipeline target
  | Ast.Block stmts -> List.exists stmt_has_build_pipeline stmts
  | Ast.PipelineDef nodes ->
      List.exists (fun (_, e) -> expr_has_build_pipeline e) nodes
  | Ast.ListComp { expr; _ } -> expr_has_build_pipeline expr
  | Ast.IntentDef pairs -> List.exists (fun (_, e) -> expr_has_build_pipeline e) pairs
  | _ -> false

and stmt_has_build_pipeline = function
  | Ast.Expression e -> expr_has_build_pipeline e
  | Ast.Assignment { expr; _ } -> expr_has_build_pipeline expr
  | Ast.Reassignment { expr; _ } -> expr_has_build_pipeline expr
  | Ast.Import _ | Ast.ImportPackage _ | Ast.ImportFrom _ | Ast.ImportFileFrom _ -> false

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
  | Ast.VNull -> ()
  | Ast.VError { context; _ } ->
      Printf.printf "%s%s%s\n" color_red (Ast.Utils.value_to_string v) color_reset;
      if context <> [] then begin
        Printf.printf "%sContext:%s\n" color_gray color_reset;
        List.iter (fun (k, v) -> Printf.printf "  %s: %s\n" k (Ast.Utils.value_to_string v)) context
      end;
      flush stdout
  | Ast.VDataFrame _ | Ast.VPipeline _ ->
      print_string (Pretty_print.pretty_print_value v);
      flush stdout
  | other ->
      (match maybe_package_info other with
      | Some (name, description, functions) ->
          Printf.printf "\n  %s%s%s\n\n  %s\n\n  %sFunctions (%d):%s\n"
            color_bold name color_reset description color_blue (List.length functions) color_reset;
          List.iter (fun fn_name -> Printf.printf "    - %s\n" fn_name) functions;
          print_newline ()
      | None -> print_endline (Ast.Utils.value_to_string other));
      flush stdout

(* --- Magic Commands and Help --- *)

let handle_magic line env mode base_keys =
  let parts = String.split_on_char ' ' (String.sub line 1 (String.length line - 1)) |> List.filter (fun s -> s <> "") in
  match parts with
  | "time" :: expr_parts ->
      let expr_str = String.concat " " expr_parts in
      let start_time = Unix.gettimeofday () in
      let (result, new_env) = parse_and_eval mode env expr_str in
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
  Printf.printf "  --mode <m>        Type-check mode: repl or strict\n";
  Printf.printf "  explain <expr>    Explain a value or expression\n";
  Printf.printf "  init package      Create a new T package\n";
  Printf.printf "  init project      Create a new T project\n";
  Printf.printf "  test              Run tests in the current directory\n";
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

let cmd_run ?(unsafe=false) mode filename env =
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
  let (result, _env) = run_file mode filename env in
  match result with
  | Ast.VError _ ->
      Printf.eprintf "%s\n" (Ast.Utils.value_to_string result); exit 1
  | Ast.VNull -> ()
  | v -> print_endline (Ast.Utils.value_to_string v)

let cmd_run_expr mode expr env =
  Packages.ensure_docs_loaded ();
  let (result, _) = parse_and_eval mode env expr in
  match result with
  | Ast.VError _ ->
      Printf.eprintf "%s\n" (Ast.Utils.value_to_string result); exit 1
  | Ast.VNull -> ()
  | v -> print_endline (Ast.Utils.value_to_string v)

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

let cmd_explain mode rest env =
  Packages.ensure_docs_loaded ();
  let expr_str = String.concat " " (List.filter (fun s -> s <> "--json") rest) in
  if expr_str = "" then (Printf.eprintf "Usage: t explain <expr>\n"; exit 1)
  else begin
    let (result, env') = parse_and_eval mode env expr_str in
    let explain_expr = "explain(__explain_target__)" in
    let env'' = Ast.Env.add "__explain_target__" result env' in
    let (explain_result, _) = parse_and_eval mode env'' explain_expr in
    print_endline (Ast.Utils.value_to_string explain_result)
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
  match Release_manager.get_package_version dir with
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
  | Ok v ->
      Printf.printf "Publishing v%s...\n" v;
      match Release_manager.validate_clean_git () with
      | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
      | Ok () ->
          match Release_manager.validate_tests_pass () with
          | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
          | Ok () ->
              match Release_manager.create_git_tag v with
              | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
              | Ok tag ->
                  match Release_manager.push_git_tag tag with
                  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
                  | Ok () -> Printf.printf "Successfully published %s\n" tag

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

let get_nix_version () =
  try
    let ch = Unix.open_process_in "nix --version" in
    let line = input_line ch in
    match Unix.close_process_in ch with
    | Unix.WEXITED 0 ->
        let parts = String.split_on_char ' ' line in
        let rec last = function [] -> "" | [x] -> x | _ :: xs -> last xs in
        Some (last parts)
    | _ -> None
  with _ -> None

let cmd_repl mode env =
  Packages.ensure_docs_loaded ();
  
  (* Track base environment keys to filter %objects *)
  let base_keys = Hashtbl.create 200 in
  Ast.Env.iter (fun k _ -> Hashtbl.add base_keys k ()) env;

  match get_nix_version () with
  | None ->
      Printf.eprintf "Nix not found! Install Nix to use T!\n";
      exit 1
  | Some nix_version ->
      Printf.printf "T, a reproducibility-first programming language for declarative\n";
      Printf.printf "data manipulation and statistical analysis.\n";
      Printf.printf "Version %s using Nix %s\n" version nix_version;
      Printf.printf "Licensed under the EUPL v1.2. No warranties.\n";
      Printf.printf "This software is in alpha and is entirely LLM-generated — caveat emptor.\n";
      Printf.printf "Website: https://tstats-project.org\n";
      Printf.printf "Contributions are welcome!\n";
      Printf.printf "Type :quit or :q to exit, :help for commands.\n\n";
      Printf.printf "%s\n\n" (Import_registry.startup_rename_warning_message ());

      (* Try to load documentation *)
  let docs_path = "help/docs.json" in
  if Sys.file_exists docs_path then begin
    Tdoc_registry.load_from_json docs_path
  end else begin
    (* Try alternate path or legacy location *)
    let docs_path = "docs.json" in
    if Sys.file_exists docs_path then begin
      Tdoc_registry.load_from_json docs_path
    end
  end;

  let scope = Symbol_table.create_scope () in
  Symbol_table.register_keywords scope;
  Symbol_table.populate_from_env scope env;

  LNoise.set_multiline true;
  LNoise.set_completion_callback (fun buffer completions ->
    let matches = Completion.complete scope ~buffer ~cursor:(String.length buffer) in
    List.iter (LNoise.add_completion completions) matches
  );

  LNoise.set_hints_callback (fun buffer ->
    let cursor = String.length buffer in
    if cursor = 0 then None
    else
      let matches = Completion.complete scope ~buffer ~cursor in
      match matches with
      | m :: _ ->
          let prefix = Completion.extract_prefix buffer cursor in
          if String.length m > String.length prefix then
             let hint = String.sub m (String.length prefix) (String.length m - String.length prefix) in
             Some (hint, LNoise.White, false)
          else None
      | [] -> None
  );

  flush stdout;
  let rec repl env =
    let prompt = "T> " in
    match LNoise.linenoise prompt with
    | None ->
        print_endline "\nGoodbye."
    | Some line ->
        let trimmed = String.trim line in
        if trimmed = "" then repl env
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
            repl env
          end
          else if trimmed = ":version" then begin
            Printf.printf "T language version %s\n" version;
            flush stdout;
            repl env
          end
          else if trimmed = ":packages" then begin
            List.iter (fun (pkg : Packages.package_info) ->
              Printf.printf "  %-12s  %s\n" pkg.name pkg.description
            ) Packages.all_packages;
            print_newline ();
            flush stdout;
            repl env
          end
          else if String.length trimmed > 0 && trimmed.[0] = '%' then begin
            let (new_env, handled) = handle_magic trimmed env mode base_keys in
            if handled then (
              ignore (LNoise.history_add line);
              ignore (LNoise.history_save ~filename:history_file);
              repl new_env
            ) else repl env
          end
          else begin
            (* Multi-line input: accumulate lines while expression is incomplete *)
            let rec read_multiline acc =
              let combined = acc in
              if is_incomplete combined then begin
                match LNoise.linenoise ".. " with
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
              end else
                combined
            in
            let full_input = read_multiline trimmed in
            ignore (LNoise.history_add full_input);
            ignore (LNoise.history_save ~filename:history_file);
            let (result, new_env) = parse_and_eval mode env full_input in
            Symbol_table.populate_from_env scope new_env;
            repl_display_value result;
            repl new_env
          end
        end
  in
  repl env

(* --- Entry Point --- *)

let () =
  Sys.catch_break true;
  let raw_args = Array.to_list Sys.argv in
  let rec extract_mode acc = function
    | [] -> (List.rev acc, Typecheck.Repl)
    | "--mode" :: [] ->
        Printf.eprintf "Missing value for --mode. Use --mode repl|strict\n";
        exit 1
    | "--mode" :: m :: rest ->
        (match Typecheck.mode_of_string m with
         | Some mode -> (List.rev_append acc rest, mode)
         | None ->
             Printf.eprintf "Invalid mode '%s'. Use --mode repl|strict\n" m;
             exit 1)
    | x :: xs -> extract_mode (x :: acc) xs
  in
  let args, mode = extract_mode [] raw_args in
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
--# @return :: Null
--# @example
--#   t_run("src/my_script.t")
--# @family repl
--# @export
*)
  let env = Ast.Env.add "t_run"
    (Ast.VBuiltin { b_name = Some "t_run"; b_arity = 1; b_variadic = false;
      b_func = (fun named_args env_ref ->
        match List.map snd named_args with
        | [Ast.VString filename] ->
            (try
              let ch = open_in filename in
              let content = really_input_string ch (in_channel_length ch) in
              close_in ch;
              let lexbuf = Lexing.from_string content in
              (try
                let program = Parser.program Lexer.token lexbuf in
                let (v, new_env) = Eval.eval_program program !env_ref in
                (match v with
                 | Ast.VError _ -> v
                 | _ -> 
                     env_ref := new_env;
                     Printf.printf "Ran %s successfully.\n" filename; flush stdout; Ast.VNull)
               with
               | Lexer.SyntaxError msg ->
                   let pos = Lexing.lexeme_start_p lexbuf in
                   make_located_error ~file:filename Ast.SyntaxError ("Syntax error in '" ^ filename ^ "': " ^ msg) pos
               | Parser.Error ->
                   let pos = Lexing.lexeme_start_p lexbuf in
                   make_located_error ~file:filename Ast.SyntaxError (Printf.sprintf "Parse error in '%s'" filename) pos)
             with
             | Sys_error msg ->
                 Ast.VError { code = Ast.FileError; message = Printf.sprintf "t_run failed: %s" msg; context = []; location = None })
        | _ -> Ast.VError { code = Ast.TypeError; message = "t_run expects a file path string."; context = []; location = None })
    })
    env
  in
(*
--# Run tests
--#
--# Runs the test suite for the current package.
--# Wraps the CLI `t test` command for use within the REPL.
--#
--# @name t_test
--# @return :: Null Returns Null on success, or an Error if tests fail.
--# @family repl
--# @export
*)
  let env = Ast.Env.add "t_test"
    (Ast.VBuiltin { b_name = Some "t_test"; b_arity = 0; b_variadic = false;
      b_func = (fun _named_args _env_ref ->
        let dir = Sys.getcwd () in
        let suite_result = Test_discovery.run_suite ~verbose:false dir in
        if suite_result.failed > 0 then
          Ast.VError { code = Ast.GenericError; message = Printf.sprintf "%d test(s) failed." suite_result.failed; context = []; location = None }
        else begin
          Printf.printf "All %d test(s) passed.\n" suite_result.passed;
          flush stdout;
          Ast.VNull
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
            Ast.VNull
        | [Ast.VString "generate"] ->
            let dir = Sys.getcwd () in
            Printf.printf "Generating Markdown in docs/reference...\n";
            let ensure_dir path =
              if Sys.file_exists path then
                (if not (Sys.is_directory path) then
                  failwith (Printf.sprintf "%s exists and is not a directory" path))
              else
                Unix.mkdir path 0o755
            in
            let docs_dir = Filename.concat dir "docs" in
            ensure_dir docs_dir;
            let out_dir = Filename.concat docs_dir "reference" in
            ensure_dir out_dir;
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
            Ast.VNull
        | [Ast.VString other] ->
            Ast.VError { code = Ast.ValueError; message = Printf.sprintf "t_doc expects \"parse\" or \"generate\", got \"%s\"." other; context = []; location = None }
        | _ -> Ast.VError { code = Ast.TypeError; message = "t_doc expects a string argument: \"parse\" or \"generate\"."; context = []; location = None })
    })
    env
  in

  (* Extract --unsafe flag *)
  let unsafe = List.mem "--unsafe" raw_args in
  let args = if unsafe then List.filter (fun s -> s <> "--unsafe") args else args in
  match args with
  | _ :: "run" :: [] ->
      Printf.eprintf "Usage: t run <file.t> | t run --expr <expr>\n";
      exit 1
  | _ :: "run" :: "--expr" :: [] ->
      Printf.eprintf "Missing expression after --expr.\n";
      exit 1
  | _ :: "run" :: "--expr" :: _ :: _ :: _ ->
      Printf.eprintf "Unexpected arguments after `t run --expr <expr>`.\n";
      exit 1
  | _ :: "run" :: "--expr" :: expr :: [] ->
      let script_mode = if mode = Typecheck.Repl && not (List.mem "--mode" raw_args) then Typecheck.Strict else mode in
      cmd_run_expr script_mode expr env
  | _ :: "run" :: filename :: [] ->
      (* Default to Strict mode for scripts, but allow --mode to override *)
      let script_mode = if mode = Typecheck.Repl && not (List.mem "--mode" raw_args) then Typecheck.Strict else mode in
      cmd_run ~unsafe script_mode filename env
  | _ :: "run" :: _ :: _ ->
      Printf.eprintf "Unexpected arguments after `t run <file.t>`.\n";
      exit 1
  | _ :: "repl" :: _ -> cmd_repl mode env
  | _ :: "explain" :: rest -> cmd_explain mode rest env
  | _ :: "init" :: "package" :: rest -> cmd_init_package rest
  | _ :: "init" :: "project" :: rest -> cmd_init_project rest
  | _ :: "test" :: rest -> cmd_test rest
  | _ :: "doctor" :: _ -> cmd_doctor ()
  | _ :: "docs" :: _ -> cmd_docs ()
  | _ :: "doc" :: rest -> cmd_doc rest
  | _ :: "update" :: _ -> cmd_update ()
  | _ :: "publish" :: _ -> cmd_publish ()

  | _ :: "init" :: _ ->
      Printf.eprintf "Usage: t init package|project <name> [options]\n";
      Printf.eprintf "Run 't init package --help' for more information.\n";
      exit 1
  | _ :: "--help" :: _ | _ :: "-h" :: _ -> print_help ()
  | _ :: "--version" :: _ | _ :: "-v" :: _ -> print_version ()
  | [_] ->
      (* No arguments: start the REPL (default behavior) *)
      cmd_repl mode env
  | _ :: unknown :: _ ->
      Printf.eprintf "Unknown command: %s\n" unknown;
      Printf.eprintf "Run 't --help' for usage information.\n";
      exit 1
  | [] -> cmd_repl mode env
