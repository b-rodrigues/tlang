(* src/package_manager/test_discovery.ml *)
(* Test runner for T packages: discovers and runs test-*.t files *)

(** Single test result *)
type test_result = {
  file : string;
  success : bool;
  error_msg : string option;
  duration : float;
}

(** Overall test suite result *)
type suite_result = {
  total : int;
  passed : int;
  failed : int;
  results : test_result list;
  total_duration : float;
}

(** Discover test files in a directory.
    Matches files named test-*.t or *_test.t, recursively. *)
let discover_tests (dir : string) : string list =
  let results = ref [] in
  let rec scan path =
    if Sys.file_exists path && Sys.is_directory path then begin
      let entries = Sys.readdir path in
      Array.sort String.compare entries;
      Array.iter (fun entry ->
        let full_path = Filename.concat path entry in
        if Sys.is_directory full_path then
          scan full_path
        else if Filename.check_suffix entry ".t" then begin
          (* Match test-*.t or *_test.t *)
          let base = Filename.remove_extension entry in
          let is_test_prefix =
            String.length base >= 5 &&
            String.sub base 0 5 = "test-" in
          let is_test_suffix =
            String.length base >= 5 &&
            String.sub base (String.length base - 5) 5 = "_test" in
          if is_test_prefix || is_test_suffix then
            results := full_path :: !results
        end
      ) entries
    end
  in
  scan dir;
  List.rev !results

(** Run a single test file in an isolated environment.
    Returns a test_result indicating pass/fail. *)
let run_test_file (file : string) : test_result =
  let start = Unix.gettimeofday () in
  try
    let ch = open_in file in
    let content = really_input_string ch (in_channel_length ch) in
    close_in ch;
    (* Create fresh isolated environment for each test *)
    let env = Eval.initial_env () in

    (* Pre-load all .t files from src/ directory if it exists *)
    let src_dir = Filename.concat (Filename.dirname (Filename.dirname file)) "src" in
    let env =
      if Sys.file_exists src_dir && Sys.is_directory src_dir then begin
        let entries = Sys.readdir src_dir in
        Array.sort String.compare entries;
        Array.fold_left (fun env entry ->
          if Filename.check_suffix entry ".t" then begin
            let src_file = Filename.concat src_dir entry in
            let ch = open_in src_file in
            let src_content = really_input_string ch (in_channel_length ch) in
            close_in ch;
            let lexbuf = Lexing.from_string src_content in
            try
              let program = Parser.program Lexer.token lexbuf in
              let rec eval_imports env = function
                | [] -> env
                | stmt :: rest ->
                    let (_, new_env) = Eval.eval_statement env stmt in
                    eval_imports new_env rest
              in
              eval_imports env program
            with _ -> env (* Ignore errors in src for now, or maybe report? *)
          end else env
        ) env entries
      end else env
    in

    let lexbuf = Lexing.from_string content in
    let program = Parser.program Lexer.token lexbuf in
    (* Evaluate all statements, collecting assertion errors *)
    let rec run_stmts env errs = function
      | [] -> (List.rev errs, env)
      | stmt :: rest ->
        let (v, new_env) = Eval.eval_statement env stmt in
        let errs' = match v with
          | Ast.VError { code = Ast.AssertionError; message; _ } ->
            message :: errs
          | Ast.VError { code; message; _ } ->
            (Printf.sprintf "%s: %s"
              (Ast.Utils.error_code_to_string code) message) :: errs
          | _ -> errs
        in
        run_stmts new_env errs' rest
    in
    let (errors, _) = run_stmts env [] program in
    let duration = Unix.gettimeofday () -. start in
    if errors = [] then
      { file; success = true; error_msg = None; duration }
    else
      { file; success = false;
        error_msg = Some (String.concat "\n  " errors);
        duration }
  with
  | Lexer.SyntaxError msg ->
    let duration = Unix.gettimeofday () -. start in
    { file; success = false;
      error_msg = Some (Printf.sprintf "Syntax Error: %s" msg);
      duration }
  | Parser.Error ->
    let duration = Unix.gettimeofday () -. start in
    { file; success = false;
      error_msg = Some "Parse Error";
      duration }
  | Sys_error msg ->
    let duration = Unix.gettimeofday () -. start in
    { file; success = false;
      error_msg = Some (Printf.sprintf "File Error: %s" msg);
      duration }
  | exn ->
    let duration = Unix.gettimeofday () -. start in
    { file; success = false;
      error_msg = Some (Printf.sprintf "Unexpected: %s" (Printexc.to_string exn));
      duration }

(** Format a duration as a human-readable string *)
let format_duration d =
  if d < 0.001 then Printf.sprintf "<1ms"
  else if d < 1.0 then Printf.sprintf "%.0fms" (d *. 1000.0)
  else Printf.sprintf "%.2fs" d

(** Run a full test suite: discover + execute all tests *)
let run_suite ?(verbose=false) (dir : string) : suite_result =
  let test_dir = Filename.concat dir "tests" in
  if not (Sys.file_exists test_dir && Sys.is_directory test_dir) then begin
    Printf.printf "No tests/ directory found.\n";
    { total = 0; passed = 0; failed = 0; results = []; total_duration = 0.0 }
  end else begin
    let files = discover_tests test_dir in
    if files = [] then begin
      Printf.printf "No test files found (looking for test-*.t or *_test.t).\n";
      { total = 0; passed = 0; failed = 0; results = []; total_duration = 0.0 }
    end else begin
      let start_total = Unix.gettimeofday () in
      Printf.printf "Running %d test file%s...\n\n"
        (List.length files) (if List.length files > 1 then "s" else "");
      let results = List.map (fun file ->
        let r = run_test_file file in
        let short_name = 
          if String.length file > String.length dir + 1 then
            String.sub file (String.length dir + 1) (String.length file - String.length dir - 1)
          else file
        in
        if r.success then
          Printf.printf "  ✓ %s (%s)\n" short_name (format_duration r.duration)
        else begin
          Printf.printf "  ✗ %s (%s)\n" short_name (format_duration r.duration);
          if verbose then
            match r.error_msg with
            | Some msg -> Printf.printf "    → %s\n" msg
            | None -> ()
        end;
        r
      ) files in
      let total_duration = Unix.gettimeofday () -. start_total in
      let passed_results = List.filter (fun r -> r.success) results in
      let passed = List.length passed_results in
      let failed = List.length results - passed in
      Printf.printf "\n";
      if failed = 0 then
        Printf.printf "✓ All %d test%s passed (%s)\n"
          passed (if passed > 1 then "s" else "") (format_duration total_duration)
      else begin
        Printf.printf "✗ %d/%d test%s failed (%s)\n\n"
          failed (List.length results)
          (if List.length results > 1 then "s" else "")
          (format_duration total_duration);
        (* Show failure details *)
        List.iter (fun r ->
          if not r.success then begin
            Printf.printf "FAIL: %s\n" r.file;
            match r.error_msg with
            | Some msg -> Printf.printf "  %s\n" msg
            | None -> ()
          end
        ) results
      end;
      { total = List.length results; passed; failed; results; total_duration }
    end
  end
