(* src/package_manager/test_discovery.ml *)
(* Test runner for T packages: discovers and runs test-*.t, test_*.t, or *_test.t files *)

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
    Matches files named test-*.t, test_*.t, or *_test.t, recursively.
    Respects ignore patterns from tests/.tignore *)
let discover_tests ?(ignore_patterns=[]) (dir : string) : string list =
  let results = ref [] in
  let rec scan path =
    if Sys.file_exists path && Sys.is_directory path then begin
      let entries =
        try Sys.readdir path
        with Sys_error _ -> [||]
      in
      Array.sort String.compare entries;
      Array.iter (fun entry ->
        let full_path = Filename.concat path entry in
        if Sys.is_directory full_path then
          scan full_path
        else if Filename.check_suffix entry ".t" then begin
          (* Match test-*.t, test_*.t, or *_test.t *)
          let base = Filename.remove_extension entry in
          let is_test_prefix =
            String.length base >= 5 &&
            String.sub base 0 5 = "test-" in
          let is_test_underscore =
            String.length base >= 5 &&
            String.sub base 0 5 = "test_" in
          let is_test_suffix =
            String.length base >= 5 &&
            String.sub base (String.length base - 5) 5 = "_test" in
          if is_test_prefix || is_test_underscore || is_test_suffix then begin
            (* Check against ignore patterns *)
            let rel_path =
              if String.length full_path > String.length dir + 1 then
                String.sub full_path (String.length dir + 1) (String.length full_path - String.length dir - 1)
              else full_path
            in
            let ignored = List.exists (fun pat ->
              (* Simple glob matching: * matches anything except / *)
              let pat_len = String.length pat in
              if pat_len = 0 then false
              else if pat.[0] = '#' then false
              else
                (* Check if pattern matches the filename or relative path *)
                let pat_base =
                  if Filename.is_relative pat then Filename.basename pat
                  else pat
                in
                let pat_base_len = String.length pat_base in
                if pat_base_len = 0 then false
                else
                  (* Try to match the pattern against the filename *)
                  let file_base = Filename.basename rel_path in
                  let file_base_len = String.length file_base in
                  if pat_base = file_base then true
                  else if pat_base = rel_path then true
                  else if Filename.check_suffix pat_base ".t" then begin
                    (* Try matching with * wildcard *)
                    let star_pos = try Some (String.index pat_base '*') with Not_found -> None in
                    match star_pos with
                    | None -> false
                    | Some sp ->
                      let prefix = String.sub pat_base 0 sp in
                      let suffix = String.sub pat_base (sp + 1) (pat_base_len - sp - 1) in
                      let prefix_len = String.length prefix in
                      let suffix_len = String.length suffix in
                      file_base_len >= prefix_len + suffix_len &&
                      String.sub file_base 0 prefix_len = prefix &&
                      (suffix_len = 0 || String.sub file_base (file_base_len - suffix_len) suffix_len = suffix)
                  end
                  else false
            ) ignore_patterns in
            if not ignored then
              results := full_path :: !results
          end
        end
      ) entries
    end
  in
  scan dir;
  List.rev !results

(** Read ignore patterns from tests/.tignore *)
let read_tignore (dir : string) : string list =
  let tignore_path = Filename.concat dir ".tignore" in
  if Sys.file_exists tignore_path then begin
    let ch = open_in tignore_path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ch)
      (fun () ->
        let lines = ref [] in
        (try
           while true do
             let line = input_line ch in
             let trimmed = String.trim line in
             if trimmed <> "" && not (String.starts_with ~prefix:"#" trimmed) then
               lines := trimmed :: !lines
           done
         with End_of_file -> ());
        List.rev !lines)
  end else []

(** Run a single test file in an isolated environment.
    Returns a test_result indicating pass/fail. *)
let run_test_file (file : string) : test_result =
  let start = Unix.gettimeofday () in
  try
    let content =
      let ch = open_in file in
      Fun.protect
        ~finally:(fun () -> close_in_noerr ch)
        (fun () -> really_input_string ch (in_channel_length ch))
    in
    (* Create fresh isolated environment for each test *)
    let env = Packages.init_env () in

    (* Pre-load all .t files from src/ directory if it exists *)
    let src_dir = Filename.concat (Filename.dirname (Filename.dirname file)) "src" in
    let env =
      if Sys.file_exists src_dir && Sys.is_directory src_dir then begin
        let entries =
          try Sys.readdir src_dir
          with Sys_error _ -> [||]
        in
        Array.sort String.compare entries;
        Array.fold_left (fun env entry ->
          if Filename.check_suffix entry ".t" then begin
            let src_file = Filename.concat src_dir entry in
            try
              let src_content =
                let ch = open_in src_file in
                Fun.protect
                  ~finally:(fun () -> close_in_noerr ch)
                  (fun () -> really_input_string ch (in_channel_length ch))
              in
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
              with
              | Out_of_memory | Stack_overflow as exn -> raise exn
              | _ -> env (* Ignore errors in src for now, or maybe report? *)
            with Sys_error _ -> env
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
    let (stmt_errors, final_env) = run_stmts env [] program in
    let pipeline_errors =
      Ast.Env.fold (fun var_name value acc ->
        if Ast.Env.mem var_name env then acc
        else match value with
        | Ast.VPipeline p ->
            let p_to_run =
              if p.Ast.p_has_patterns then
                match Pipeline_expand.expand_pipeline_for_build p final_env with
                | Ok p_exp -> p_exp
                | Error _ -> p
              else p
            in
            (match Builder.populate_pipeline ~build:false p_to_run with
             | Error msg ->
                 Printf.sprintf "Pipeline '%s' validation error: %s" var_name msg :: acc
             | Ok _ -> acc)
        | _ -> acc
      ) final_env []
    in
    let errors = stmt_errors @ pipeline_errors in
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
  | Ast.Mixed_bracket_form ->
    let duration = Unix.gettimeofday () -. start in
    { file; success = false;
      error_msg = Some "Mixed bracket literal (found both single elements and key-value pairs)";
      duration }
  | Ast.Invalid_match_pattern msg ->
    let duration = Unix.gettimeofday () -. start in
    { file; success = false;
      error_msg = Some msg;
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

(** JSON serialization for test results *)
let test_result_to_yojson r =
  `Assoc [
    ("file", `String r.file);
    ("status", `String (if r.success then "passed" else "failed"));
    ("duration_ms", `Int (Int.of_float (Float.round (r.duration *. 1000.0))));
    ("error", (match r.error_msg with Some e -> `String e | None -> `Null));
  ]

let suite_result_to_yojson r =
  `Assoc [
    ("schema_version", `String "1");
    ("status", `String (if r.failed = 0 then "passed" else "failed"));
    ("total", `Int r.total);
    ("passed", `Int r.passed);
    ("failed", `Int r.failed);
    ("duration_ms", `Int (Int.of_float (Float.round (r.total_duration *. 1000.0))));
    ("results", `List (List.map test_result_to_yojson r.results));
  ]

(** Escape XML special characters *)
let xml_escape s =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | '&' -> Buffer.add_string buf "&amp;"
    | '<' -> Buffer.add_string buf "&lt;"
    | '>' -> Buffer.add_string buf "&gt;"
    | '"' -> Buffer.add_string buf "&quot;"
    | '\'' -> Buffer.add_string buf "&apos;"
    | c -> Buffer.add_char buf c
  ) s;
  Buffer.contents buf

(** JUnit XML serialization for test results *)
let suite_result_to_xml r =
  let buf = Buffer.create 1024 in
  Buffer.add_string buf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  let time_str = Printf.sprintf "%.3f" r.total_duration in
  let failures = r.failed in
  Buffer.add_string buf (Printf.sprintf "<testsuites name=\"t test\" tests=\"%d\" failures=\"%d\" time=\"%s\">\n"
    r.total failures time_str);
  Buffer.add_string buf (Printf.sprintf "  <testsuite name=\"t test\" tests=\"%d\" failures=\"%d\" time=\"%s\">\n"
    r.total failures time_str);
  List.iter (fun tr ->
    let name = xml_escape tr.file in
    let t_time = Printf.sprintf "%.3f" tr.duration in
    if tr.success then
      Buffer.add_string buf (Printf.sprintf "    <testcase name=\"%s\" time=\"%s\" />\n" name t_time)
    else begin
      let message = match tr.error_msg with
        | Some msg -> xml_escape msg
        | None -> "Test failed"
      in
      Buffer.add_string buf (Printf.sprintf "    <testcase name=\"%s\" time=\"%s\">\n" name t_time);
      Buffer.add_string buf (Printf.sprintf "      <failure message=\"%s\" type=\"TestFailure\">\n"
        (xml_escape (match tr.error_msg with Some m -> m | None -> "Test failed")));
      Buffer.add_string buf (Printf.sprintf "        %s\n" message);
      Buffer.add_string buf "      </failure>\n";
      Buffer.add_string buf "    </testcase>\n"
    end
  ) r.results;
  Buffer.add_string buf "  </testsuite>\n";
  Buffer.add_string buf "</testsuites>\n";
  Buffer.contents buf

(** Run a full test suite: discover + execute all tests *)
let run_suite ?(verbose=false) ?(quiet=false) ?(only=[]) ?(not_=[]) (dir : string) : suite_result =
  let test_dir = Filename.concat dir "tests" in
  if not (Sys.file_exists test_dir && Sys.is_directory test_dir) then begin
    if not quiet then Printf.printf "No tests/ directory found.\n";
    { total = 0; passed = 0; failed = 0; results = []; total_duration = 0.0 }
  end else begin
    let ignore_patterns = read_tignore test_dir in
    let files = discover_tests ~ignore_patterns test_dir in
    if files = [] then begin
      if not quiet then Printf.printf "No test files found (looking for test-*.t, test_*.t, or *_test.t).\n";
      { total = 0; passed = 0; failed = 0; results = []; total_duration = 0.0 }
    end else begin
      (* Apply --only filter (OR semantics: match any pattern) *)
      let files =
        if only = [] then files
        else List.filter (fun file ->
          List.exists (fun pat ->
            let rel =
              if String.length file > String.length dir + 1 then
                String.sub file (String.length dir + 1) (String.length file - String.length dir - 1)
              else file
            in
            let pat_lower = String.lowercase_ascii pat in
            let rel_lower = String.lowercase_ascii rel in
            (* Check if pattern is contained in the path *)
            let rec has_substring s sub start =
              let s_len = String.length s in
              let sub_len = String.length sub in
              if start + sub_len > s_len then false
              else if String.sub s start sub_len = sub then true
              else has_substring s sub (start + 1)
            in
            has_substring rel_lower pat_lower 0
          ) only
        ) files
      in
      (* Apply --not filter (skip files matching any pattern) *)
      let files =
        if not_ = [] then files
        else List.filter (fun file ->
          not (List.exists (fun pat ->
            let rel =
              if String.length file > String.length dir + 1 then
                String.sub file (String.length dir + 1) (String.length file - String.length dir - 1)
              else file
            in
            let pat_lower = String.lowercase_ascii pat in
            let rel_lower = String.lowercase_ascii rel in
            let rec has_substring s sub start =
              let s_len = String.length s in
              let sub_len = String.length sub in
              if start + sub_len > s_len then false
              else if String.sub s start sub_len = sub then true
              else has_substring s sub (start + 1)
            in
            has_substring rel_lower pat_lower 0
          ) not_)
        ) files
      in
      if files = [] then begin
        if not quiet then Printf.printf "No test files matched the filters.\n";
        { total = 0; passed = 0; failed = 0; results = []; total_duration = 0.0 }
      end else begin
        let start_total = Unix.gettimeofday () in
        if not quiet then Printf.printf "Running %d test file%s...\n\n"
          (List.length files) (if List.length files > 1 then "s" else "");
        let results = List.map (fun file ->
          let r = run_test_file file in
          let short_name = 
            if String.length file > String.length dir + 1 then
              String.sub file (String.length dir + 1) (String.length file - String.length dir - 1)
            else file
          in
          if not quiet then begin
            if r.success then
              Printf.printf "  ✓ %s (%s)\n" short_name (format_duration r.duration)
            else begin
              Printf.printf "  ✗ %s (%s)\n" short_name (format_duration r.duration);
              if verbose then
                match r.error_msg with
                | Some msg -> Printf.printf "    → %s\n" msg
                | None -> ()
            end
          end;
          r
        ) files in
        let total_duration = Unix.gettimeofday () -. start_total in
        let passed_results = List.filter (fun r -> r.success) results in
        let passed = List.length passed_results in
        let failed = List.length results - passed in
        if not quiet then begin
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
          end
        end;
        { total = List.length results; passed; failed; results; total_duration }
      end
    end
  end
