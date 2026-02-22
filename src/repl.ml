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

let parse_and_eval mode env input =
  let lexbuf = Lexing.from_string input in
  try
    let program = Parser.program Lexer.token lexbuf in
    match Typecheck.validate_program ~mode program with
    | Error msg -> (Ast.VError { code = Ast.TypeError; message = msg; context = [] }, env)
    | Ok () -> Eval.eval_program program env
  with
  | Lexer.SyntaxError msg ->
      (Ast.VError { code = Ast.GenericError; message = "Syntax Error: " ^ msg; context = [] }, env)
  | Parser.Error ->
      let pos = Lexing.lexeme_start_p lexbuf in
      let msg = Printf.sprintf "Parse Error at line %d, column %d"
        pos.Lexing.pos_lnum
        (pos.Lexing.pos_cnum - pos.Lexing.pos_bol)
      in
      (Ast.VError { code = Ast.GenericError; message = msg; context = [] }, env)

let run_file mode filename env =
  try
    let ch = open_in filename in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    parse_and_eval mode env content
  with
  | Sys_error msg -> (Ast.VError { code = Ast.FileError; message = "File Error: " ^ msg; context = [] }, env)

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
      List.exists (fun (n : Ast.pipeline_node) -> expr_has_build_pipeline n.node_expr) nodes
  | Ast.ListComp { expr; _ } -> expr_has_build_pipeline expr
  | Ast.IntentDef pairs -> List.exists (fun (_, e) -> expr_has_build_pipeline e) pairs
  | _ -> false

and stmt_has_build_pipeline = function
  | Ast.Expression e -> expr_has_build_pipeline e
  | Ast.Assignment { expr; _ } -> expr_has_build_pipeline expr
  | Ast.Reassignment { expr; _ } -> expr_has_build_pipeline expr
  | Ast.Import _ | Ast.ImportPackage _ | Ast.ImportFrom _ -> false

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
  | Ast.VError _ | Ast.VDataFrame _ | Ast.VPipeline _ ->
      print_string (Pretty_print.pretty_print_value v);
      flush stdout
  | other ->
      (match maybe_package_info other with
      | Some (name, description, functions) ->
          Printf.printf "\n  %s\n\n  %s\n\n  Functions (%d):\n"
            name description (List.length functions);
          List.iter (fun fn_name -> Printf.printf "    - %s\n" fn_name) functions;
          print_newline ()
      | None -> print_endline (Ast.Utils.value_to_string other))

(* --- CLI Commands --- *)

let print_help () =
  Printf.printf "T language — version %s\n\n" version;
  Printf.printf "Usage: t <command> [arguments]\n\n";
  Printf.printf "Commands:\n";
  Printf.printf "  repl              Start the interactive REPL\n";
  Printf.printf "  run <file.t>      Execute a T source file\n";
  Printf.printf "  --mode <m>        Type-check mode: repl (default) or strict\n";
  Printf.printf "  explain <expr>    Explain a value or expression\n";
  Printf.printf "  init package <n>  Create a new T package\n";
  Printf.printf "  init project <n>  Create a new T project\n";

  Printf.printf "  test              Run tests in the current directory\n";
  Printf.printf "  doctor            Check package configuration and health\n";
  Printf.printf "  docs              Open package documentation\n";
  Printf.printf "  doc               Generate documentation from source (--parse, --generate)\n";
  Printf.printf "  update            Update dependencies (nix flake update)\n";
  Printf.printf "  publish           Draft a new release (tag + push)\n";
  Printf.printf "  --help, -h        Show this help message\n";
  Printf.printf "  --version, -v     Show version information\n";
  Printf.printf "\nStandard packages (loaded by default):\n";
  Printf.printf "  core              Printing, type inspection, data structures\n";
  Printf.printf "  math              Pure numerical primitives (sqrt, abs, log, exp, pow)\n";
  Printf.printf "  stats             Statistical summaries and models (mean, sd, lm, ...)\n";
  Printf.printf "  colcraft          DataFrame manipulation (select, filter, mutate, ...)\n";
  Printf.printf "  dataframe         DataFrame creation and introspection\n";
  Printf.printf "  base              Assertions, NA handling, error utilities\n";
  Printf.printf "  pipeline          Pipeline definition and introspection\n";
  Printf.printf "  explain           Value introspection and intent blocks\n";
  Printf.printf "\nExamples:\n";
  Printf.printf "  t repl\n";
  Printf.printf "  t run pipeline.t\n";
  Printf.printf "  t explain 'read_csv(\"data.csv\")'\n";
  Printf.printf "  t init package my-stats-pkg\n";
  Printf.printf "  t init project my-analysis\n"

let print_version () =
  Printf.printf "T language version %s\n" version

let cmd_run ?(unsafe=false) mode filename env =
  Packages.ensure_docs_loaded ();
  (* Gate: non-interactive execution requires build_pipeline() unless --unsafe *)
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
          Printf.eprintf "Scripts run with `t run` must call `populate_pipeline(p, build=true)` or `build_pipeline()`.\n";
          Printf.eprintf "Use the REPL for interactive exploration, or pass --unsafe to override.\n";
          exit 1
        end
      with _ -> ())  (* If parsing fails here, let the actual run_file handle the error *)
    with _ -> ()  (* If file open fails, let run_file handle it *)
  end;
  let (result, _env) = run_file mode filename env in
  match result with
  | Ast.VError { code; message; _ } ->
      Printf.eprintf "Error(%s): %s\n" (Ast.Utils.error_code_to_string code) message; exit 1
  | Ast.VNull -> ()
  | v -> print_endline (Ast.Utils.value_to_string v)

let cmd_init_package args =
  match Scaffold.parse_init_flags args with
  | Error msg -> 
      (* If no args provided, default to interactive *)
      if args = [] then
        let opts = Scaffold.interactive_init "" in
        match Scaffold.scaffold_package opts with
        | Ok () -> Printf.printf "Package %s initialized successfully.\n" opts.target_name
        | Error e -> Printf.eprintf "Error: %s\n" e; exit 1
      else (Printf.eprintf "Error: %s\n" msg; exit 1)
  | Ok opts ->
      let opts = if opts.interactive then Scaffold.interactive_init opts.target_name else opts in
      match Scaffold.scaffold_package opts with
      | Ok () -> Printf.printf "Package %s initialized successfully.\n" opts.target_name
      | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1

let cmd_init_project args =
  match Scaffold.parse_init_flags args with
  | Error msg -> 
      (* If no args provided, default to interactive *)
      if args = [] then
        let opts = Scaffold.interactive_init ~placeholder:"my_project" "" in
        match Scaffold.scaffold_project opts with
        | Ok () -> Printf.printf "Project %s initialized successfully.\n" opts.target_name
        | Error e -> Printf.eprintf "Error: %s\n" e; exit 1
      else (Printf.eprintf "Error: %s\n" msg; exit 1)
  | Ok opts ->
      let opts = if opts.interactive then Scaffold.interactive_init ~placeholder:"my_project" opts.target_name else opts in
      match Scaffold.scaffold_project opts with
      | Ok () -> Printf.printf "Project %s initialized successfully.\n" opts.target_name
      | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1

let cmd_explain mode rest env =
  Packages.ensure_docs_loaded ();
  let is_json = List.mem "--json" rest in
  let expr_parts = List.filter (fun s -> s <> "--json") rest in
  let expr_str = String.concat " " expr_parts in
  if expr_str = "" then begin
    Printf.eprintf "Usage: t explain <expression> [--json]\n"; exit 1
  end else begin
    let (result, env') = parse_and_eval mode env expr_str in
    match result with
    | Ast.VError { code; message; _ } ->
        Printf.eprintf "Error(%s): %s\n" (Ast.Utils.error_code_to_string code) message; exit 1
    | _ ->
        let explain_expr = Printf.sprintf "explain(__explain_target__)" in
        let env'' = Ast.Env.add "__explain_target__" result env' in
        let (explain_result, _) = parse_and_eval mode env'' explain_expr in
        if is_json then
          print_endline (Ast.Utils.value_to_string explain_result)
        else begin
          let rec print_dict indent pairs =
            List.iter (fun (k, v) ->
              match v with
              | Ast.VDict sub_pairs ->
                  Printf.printf "%s%s:\n" indent k;
                  print_dict (indent ^ "  ") sub_pairs
              | Ast.VList items ->
                  Printf.printf "%s%s: [%s]\n" indent k
                    (String.concat ", " (List.map (fun (_, item) -> Ast.Utils.value_to_string item) items))
              | _ ->
                  Printf.printf "%s%s: %s\n" indent k (Ast.Utils.value_to_string v)
            ) pairs
          in
          match explain_result with
          | Ast.VDict pairs -> print_dict "" pairs
          | Ast.VError { code; message; _ } ->
              Printf.eprintf "Error(%s): %s\n" (Ast.Utils.error_code_to_string code) message; exit 1
          | v -> print_endline (Ast.Utils.value_to_string v)
        end
  end

let cmd_test args =
  let verbose = List.mem "--verbose" args || List.mem "-v" args in
  let dir = Sys.getcwd () in
  let suite_result = Test_discovery.run_suite ~verbose dir in
  if suite_result.failed > 0 then exit 1 else ()

let cmd_doctor () =
  Package_doctor.run_doctor ()

let cmd_publish () =
  let dir = Sys.getcwd () in
  match Release_manager.get_package_version dir with
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
  | Ok version ->
      Printf.printf "Preparing to publish version %s...\n" version;
      match Release_manager.validate_clean_git () with
      | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
      | Ok () ->
          match Release_manager.validate_tests_pass () with
          | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
          | Ok () ->
              match Release_manager.validate_changelog dir version with
              | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
              | Ok () ->
                  Printf.printf "\n✓ Validation complete.\n";
                  Printf.printf "  - Git working directory is clean\n";
                  Printf.printf "  - Tests pass\n";
                  Printf.printf "  - CHANGELOG.md has entry for %s\n" version;
                  Printf.printf "\nProceed to tag and push v%s? [y/N] " version;
                  flush stdout;
                  let response = try read_line () with End_of_file -> "n" in
                  if String.lowercase_ascii response = "y" then begin
                    match Release_manager.create_git_tag version with
                    | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
                    | Ok tag ->
                        Printf.printf "✓ Tag %s created locally.\n" tag;
                        match Release_manager.push_git_tag tag with
                        | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1
                        | Ok () -> Printf.printf "✓ Tag %s pushed to remote.\n" tag
                  end else
                    Printf.printf "Aborted.\n"


let cmd_docs () =
  let dir = Sys.getcwd () in
  match Documentation_manager.validate_docs dir with
  | Ok () -> Documentation_manager.open_docs dir
  | Error msg -> 
      Printf.eprintf "Documentation check failed: %s\n" msg;
      Printf.printf "Opening README as fallback...\n";
      Documentation_manager.open_docs dir

let recursive_files dir =
  if not (Sys.file_exists dir && Sys.is_directory dir) then
    []
  else
  let rec walk acc d =
    let entries = Sys.readdir d in
    Array.fold_left (fun acc e ->
      let path = Filename.concat d e in
      if Sys.is_directory path then walk acc path
      else if Filename.check_suffix path ".ml" || Filename.check_suffix path ".t" then path :: acc
      else acc
    ) acc entries
  in
  walk [] dir

let cmd_doc args =
  let do_parse = List.mem "--parse" args || args = [] in
  let do_gen = List.mem "--generate" args || args = [] in
  let dir = Sys.getcwd () in
  let src_dir = Filename.concat dir "src" in
  
  if do_parse then begin
    Printf.printf "Parsing documentation from %s...\n" src_dir;
    let files = recursive_files src_dir in
    List.iter (fun f ->
      let docs = Tdoc_parser.parse_file f in
      List.iter Tdoc_registry.register docs
    ) files;
    
    let help_dir = Filename.concat dir "help" in
    if not (Sys.file_exists help_dir) then Unix.mkdir help_dir 0o755;
    
    Tdoc_registry.to_json_file (Filename.concat help_dir "docs.json");
    Printf.printf "Parsed %d functions.\n" (List.length (Tdoc_registry.get_all ()))
  end;
  
  if do_gen then begin
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
    List.iter (fun e ->
      let content = Tdoc_markdown.generate_function_doc e in
      let path = Filename.concat out_dir (e.name ^ ".md") in
      let ch = open_out path in
      output_string ch content;
      close_out ch
    ) entries;
    (* Generate Index *)
    let index_content = Tdoc_markdown.generate_index entries in
    let ch = open_out (Filename.concat out_dir "index.md") in
    output_string ch index_content;
    close_out ch;
    Printf.printf "Documentation generated in %s\n" out_dir
  end

let cmd_update () =
  match Update_manager.update_flake_lock () with
  | Ok () -> Printf.printf "Dependencies updated successfully.\n"
  | Error msg -> Printf.eprintf "Error: %s\n" msg; exit 1

(* --- Interactive REPL --- *) 


let get_nix_version () =
  try
    let ch = Unix.open_process_in "nix --version" in
    let line = input_line ch in
    match Unix.close_process_in ch with
    | Unix.WEXITED 0 ->
        let parts = String.split_on_char ' ' line in
        let rec last = function
          | [] -> ""
          | [x] -> x
          | _ :: xs -> last xs
        in
        Some (last parts)
    | _ -> None
  with _ -> None

let cmd_repl mode env =
  Packages.ensure_docs_loaded ();
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

  flush stdout;
  let rec repl env =
    match LNoise.linenoise "T> " with
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
            repl_display_value result;
            repl new_env
          end
        end
  in
  repl env

(* --- Entry Point --- *)

let () =
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
                  Ast.VError { code = Ast.GenericError; message = Printf.sprintf "Syntax error in '%s': %s" filename msg; context = [] }
              | Parser.Error ->
                  let pos = Lexing.lexeme_start_p lexbuf in
                  Ast.VError { code = Ast.GenericError;
                    message = Printf.sprintf "Parse error in '%s' at line %d, column %d" filename pos.Lexing.pos_lnum (pos.Lexing.pos_cnum - pos.Lexing.pos_bol);
                    context = [] })
            with
            | Sys_error msg ->
                Ast.VError { code = Ast.FileError; message = Printf.sprintf "t_run failed: %s" msg; context = [] })
        | _ -> Ast.VError { code = Ast.TypeError; message = "t_run expects a file path string."; context = [] })
    })
    env
  in
  let env = Ast.Env.add "t_test"
    (Ast.VBuiltin { b_name = Some "t_test"; b_arity = 0; b_variadic = false;
      b_func = (fun _named_args _env_ref ->
        let dir = Sys.getcwd () in
        let suite_result = Test_discovery.run_suite ~verbose:false dir in
        if suite_result.failed > 0 then
          Ast.VError { code = Ast.GenericError; message = Printf.sprintf "%d test(s) failed." suite_result.failed; context = [] }
        else begin
          Printf.printf "All %d test(s) passed.\n" suite_result.passed;
          flush stdout;
          Ast.VNull
        end)
    })
    env
  in
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
              let content = Tdoc_markdown.generate_function_doc e in
              let path = Filename.concat out_dir (e.name ^ ".md") in
              let ch = open_out path in
              output_string ch content;
              close_out ch
            ) entries;
            let index_content = Tdoc_markdown.generate_index entries in
            let ch = open_out (Filename.concat out_dir "index.md") in
            output_string ch index_content;
            close_out ch;
            Printf.printf "Documentation generated in %s\n" out_dir;
            flush stdout;
            Ast.VNull
        | [Ast.VString other] ->
            Ast.VError { code = Ast.ValueError; message = Printf.sprintf "t_doc expects \"parse\" or \"generate\", got \"%s\"." other; context = [] }
        | _ -> Ast.VError { code = Ast.TypeError; message = "t_doc expects a string argument: \"parse\" or \"generate\"."; context = [] })
    })
    env
  in

  (* Extract --unsafe flag *)
  let unsafe = List.mem "--unsafe" raw_args in
  let args = if unsafe then List.filter (fun s -> s <> "--unsafe") args else args in
  match args with
  | _ :: "run" :: filename :: _ ->
      (* Default to Strict mode for scripts, but allow --mode to override *)
      let script_mode = if mode = Typecheck.Repl && not (List.mem "--mode" raw_args) then Typecheck.Strict else mode in
      cmd_run ~unsafe script_mode filename env
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
