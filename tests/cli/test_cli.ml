let run_tests pass_count fail_count _eval_string _eval_string_env test =
  (* This test module uses the shared test-runner signature even though it
     only needs the generic `test` helper and local counter refs. *)
  let contains text substring =
    let text_len = String.length text in
    let substring_len = String.length substring in
    if substring_len = 0 then
      true
    else begin
      let rec loop index =
        if index + substring_len > text_len then
          false
        else if String.sub text index substring_len = substring then
          true
        else
          loop (index + 1)
      in
      loop 0
    end
  in

  let test_message name predicate =
    if predicate then begin
      incr pass_count;
      Printf.printf "  ✓ %s\n" name
    end else begin
      incr fail_count;
      Printf.printf "  ✗ %s\n" name
    end
  in

  Printf.printf "Phase 7 — CLI argument parsing helpers:\n";
  let cwd = "/tmp/project" in
  let mode_ok = Cli_args.parse_mode_args ["t"; "--mode"; "strict"; "run"; "main.t"] in
  test_message "parse_mode_args accepts strict mode"
    (match mode_ok with
     | Ok parsed ->
         parsed.Cli_args.mode = Typecheck.Strict &&
         parsed.Cli_args.mode_flag &&
         parsed.Cli_args.args = ["t"; "run"; "main.t"]
     | Error _ -> false);
  test_message "parse_mode_args rejects duplicate --mode"
    (match Cli_args.parse_mode_args ["t"; "--mode"; "repl"; "--mode"; "strict"] with
     | Error msg -> contains msg "Duplicate --mode"
     | Ok _ -> false);
  test_message "parse_mode_args rejects missing mode value"
    (match Cli_args.parse_mode_args ["t"; "--mode"] with
     | Error msg -> contains msg "Missing value for --mode"
     | Ok _ -> false);
  test_message "parse_test_args defaults to cwd"
    (match Cli_args.parse_test_args ~cwd [] with
     | Ok { Cli_args.verbose = verbose; target_dir } -> (not verbose) && target_dir = cwd
     | Error _ -> false);
  test_message "parse_test_args accepts verbose flag and explicit directory"
    (match Cli_args.parse_test_args ~cwd ["--verbose"; "tests"] with
     | Ok { Cli_args.verbose = verbose; target_dir } -> verbose && target_dir = "tests"
     | Error _ -> false);
  test_message "parse_test_args rejects unknown flags"
    (match Cli_args.parse_test_args ~cwd ["--wat"] with
     | Error msg -> contains msg "Unknown option: --wat"
     | Ok _ -> false);
  test_message "parse_test_args rejects multiple directories"
    (match Cli_args.parse_test_args ~cwd ["tests"; "extra"] with
     | Error msg -> contains msg "Unexpected argument: extra"
     | Ok _ -> false);
  test_message "validate_cli_flags rejects --unsafe outside run"
    (match Cli_args.validate_cli_flags ~mode_flag:false ~unsafe_flag:true ~failfast_flag:false ["t"; "test"] with
     | Error msg -> contains msg "--unsafe"
     | Ok _ -> false);
  test_message "validate_cli_flags rejects --unsafe with run --expr"
    (match Cli_args.validate_cli_flags ~mode_flag:false ~unsafe_flag:true ~failfast_flag:false ["t"; "run"; "--expr"; "1+1"] with
     | Error msg -> contains msg "run --expr"
     | Ok _ -> false);
  test_message "validate_cli_flags rejects --mode with test"
    (match Cli_args.validate_cli_flags ~mode_flag:true ~unsafe_flag:false ~failfast_flag:false ["t"; "test"] with
     | Error msg -> contains msg "--mode"
     | Ok _ -> false);
  test_message "validate_cli_flags allows --mode with repl"
    (match Cli_args.validate_cli_flags ~mode_flag:true ~unsafe_flag:false ~failfast_flag:false ["t"; "repl"] with
     | Ok () -> true
     | Error _ -> false);
  test_message "init flag parsing rejects unexpected positional arguments"
    (match Scaffold.parse_init_flags ["pkg"; "extra"] with
     | Error msg -> contains msg "Unexpected argument: extra"
     | Ok _ -> false);
  print_newline ();

  Printf.printf "CLI — packages() builtin coverage:\n";
  test "packages returns list"
    "type(packages())"
    {|"List"|};
  test "packages count"
    "length(packages())"
    "11";
  test "package_info stats"
    {|package_info("stats").name|}
    {|"stats"|};
  test "package_info stats description"
    {|package_info("stats").description|}
    {|"Statistical summaries and models"|};
  test "package_info stats functions"
    {|type(package_info("stats").functions)|}
    {|"List"|};
  (* The colcraft_package statically defines 7 core functions:
     select, filter, mutate, arrange, group_by, ungroup, summarize.
     This test asserts that the documented/expanded functions list
     contains more entries than that static baseline.
     NOTE: Keep this list in sync with colcraft_package definition in packages.ml *)
  test "package_info colcraft functions are expanded"
    {|length(package_info("colcraft").functions) > 7|}
    "true";
  test "package_info missing"
    {|package_info("nonexistent")|}
    {|Error(KeyError: "Package `nonexistent` not found.")|};
  test "package_info core"
    {|package_info("core").name|}
    {|"core"|};
  test "package_info colcraft"
    {|package_info("colcraft").name|}
    {|"colcraft"|};
  test "package_info strcraft"
    {|package_info("strcraft").name|}
    {|"strcraft"|};
  test "package_info strcraft functions include str_substring"
    {|contains(str_join(package_info("strcraft").functions, ","), "str_substring")|}
    "true";
  test "package_info strcraft functions include str_nchar"
    {|contains(str_join(package_info("strcraft").functions, ","), "str_nchar")|}
    "true";
  test "package_info core excludes str_substring"
    {|contains(str_join(package_info("core").functions, ","), "str_substring")|}
    "false";
  test "package_info core excludes str_nchar"
    {|contains(str_join(package_info("core").functions, ","), "str_nchar")|}
    "false";
  test "package_info math"
    {|package_info("math").name|}
    {|"math"|};
  test "package_info lens"
    {|package_info("lens").name|}
    {|"lens"|};
  test "package_info lens functions"
    {|length(package_info("lens").functions)|}
    "12";
  test "package_info non-string"
    "package_info(42)"
    {|Error(TypeError: "Function `package_info` expects a string argument.")|};
  let warning = Import_registry.startup_rename_warning_message () in
  test_message "startup rename warning mentions builtin conflicts"
    (contains warning "built-in function");
  test_message "startup rename warning mentions package-prefixed names"
    (contains warning "<package>_<function>");
  test_message "startup rename warning explains why names change"
    (contains warning "silently overwriting another");
  test_message "docs path derived from nix executable path"
    (Packages.docs_path_from_executable_path "/nix/store/abc123-t-lang-0.1.0/bin/t" =
       Some "/nix/store/abc123-t-lang-0.1.0/share/tlang/help/docs.json");
  let original_docs_path = Sys.getenv_opt "TLANG_DOCS_PATH" in
  let docs_search_paths =
    Fun.protect
      ~finally:(fun () ->
        match original_docs_path with
        | Some value -> Unix.putenv "TLANG_DOCS_PATH" value
        | None -> Unix.putenv "TLANG_DOCS_PATH" "")
      (fun () ->
        Unix.putenv "TLANG_DOCS_PATH" "/tmp/custom-docs.json";
        Packages.docs_search_paths ())
  in
  test_message "docs search paths prefer TLANG_DOCS_PATH override"
    (match docs_search_paths with
     | path :: _ -> path = "/tmp/custom-docs.json"
     | [] -> false);

  let original_repo_root = Sys.getenv_opt "TLANG_REPO_ROOT" in
  let repo_search_paths =
    Fun.protect
      ~finally:(fun () ->
        match original_repo_root with
        | Some value -> Unix.putenv "TLANG_REPO_ROOT" value
        | None -> Unix.putenv "TLANG_REPO_ROOT" "")
      (fun () ->
        Unix.putenv "TLANG_REPO_ROOT" "/tmp/repo";
        Packages.docs_search_paths ())
  in
  test_message "docs search paths include TLANG_REPO_ROOT fallback"
    (List.exists (fun p -> p = "/tmp/repo/help/docs.json") repo_search_paths);
  print_newline ();

  Printf.printf "Phase 7 — Pretty-print builtin:\n";
  test "pretty_print int"
    "pretty_print(42)"
    "NA";
  test "pretty_print list"
    "pretty_print([1, 2, 3])"
    "NA";
  test "pretty_print error"
    "pretty_print(1 / 0)"
    "NA";
  let ggplot_pretty =
    Pretty_print.pretty_print_value
      (Ast.VDict [
        ("class", Ast.VString "ggplot");
        ("backend", Ast.VString "R");
        ("title", Ast.VString "Fuel economy");
        ("mapping", Ast.VDict [("x", Ast.VString "wt"); ("y", Ast.VString "mpg")]);
        ("labels", Ast.VDict [("x", Ast.VString "Weight"); ("y", Ast.VString "Miles per gallon")]);
        ("layers", Ast.VList [(None, Ast.VString "Point")]);
        ("_display_keys", Ast.VList [
          (None, Ast.VString "class");
          (None, Ast.VString "backend");
          (None, Ast.VString "title");
          (None, Ast.VString "mapping");
          (None, Ast.VString "labels");
          (None, Ast.VString "layers");
        ]);
      ])
  in
  test_message "pretty_print ggplot metadata uses specialized class heading"
    (contains ggplot_pretty "ggplot {" && contains ggplot_pretty "`mapping`");
  let ggplot_trimmed_pretty =
    Pretty_print.pretty_print_value
      (Ast.VDict [
        ("class", Ast.VString "ggplot");
        ("backend", Ast.VString "R");
        ("title", Ast.VString "Fuel economy");
        ("mapping", Ast.VDict [("x", Ast.VString "wt"); ("y", Ast.VString "mpg")]);
        ("labels", Ast.VDict [("x", Ast.VString "Weight"); ("y", Ast.VString "Miles per gallon")]);
        ("layers", Ast.VList [(None, Ast.VString "Point")]);
        ("extra", Ast.VString "hidden");
        ("_display_keys", Ast.VList [
          (None, Ast.VString "class");
          (None, Ast.VString "title");
          (None, Ast.VString "layers");
        ]);
      ])
  in
  test_message "pretty_print ggplot metadata honors provided display keys"
    (contains ggplot_trimmed_pretty "ggplot {" &&
     contains ggplot_trimmed_pretty "`title`" &&
     contains ggplot_trimmed_pretty "`layers`" &&
     not (contains ggplot_trimmed_pretty "`mapping`") &&
     not (contains ggplot_trimmed_pretty "`extra`"));
  let plotnine_pretty =
    Pretty_print.pretty_print_value
      (Ast.VDict [
        ("class", Ast.VString "plotnine");
        ("backend", Ast.VString "Python");
        ("title", Ast.VString "Scatter plot");
        ("mapping", Ast.VDict [("x", Ast.VString "wt"); ("y", Ast.VString "mpg")]);
        ("labels", Ast.VDict [("x", Ast.VString "wt"); ("y", Ast.VString "mpg")]);
        ("layers", Ast.VList [(None, Ast.VString "point")]);
      ])
  in
  test_message "pretty_print plotnine metadata keeps plot class and runtime backend"
    (contains plotnine_pretty "plotnine {" && contains plotnine_pretty "\"Python\"");
  let explain_tree_pretty =
    Pretty_print.pretty_print_value
      (Ast.VDict [
        ("kind", Ast.VString "node");
        ("node_name", Ast.VString "r_node");
        ("diagnostics", Ast.VDict [
          ("warnings", Ast.VList []);
          ("error", Ast.VDict [
            ("kind", Ast.VString "RuntimeError");
            ("message", Ast.VString "boom");
          ]);
        ]);
        ("contents", Ast.VDict [
          ("kind", Ast.VString "value");
          ("type", Ast.VString "Error");
          ("error_code", Ast.VString "RuntimeError");
        ]);
        ("_display_keys", Ast.VList [
          (None, Ast.VString "kind");
          (None, Ast.VString "node_name");
          (None, Ast.VString "diagnostics");
          (None, Ast.VString "contents");
        ]);
      ])
  in
  test_message "pretty_print explain Dicts as a tree"
    (contains explain_tree_pretty "node\n" &&
     contains explain_tree_pretty "├── node_name: \"r_node\"" &&
     contains explain_tree_pretty "├── diagnostics" &&
     contains explain_tree_pretty "│   └── error" &&
     contains explain_tree_pretty "└── contents");
  let ggplot_render =
    Show_plot.render_script_for_class "ggplot" "/tmp/plot.rds"
  in
  test_message "show_plot R renderer uses readRDS and ggsave"
    (match ggplot_render with
     | Ok (script, script_name, runtime) ->
         script_name = "render_plot.R"
         && runtime = "R"
         && contains script "readRDS"
         && contains script "ggsave"
     | Error _ -> false);
  let matplotlib_render =
    Show_plot.render_script_for_class "matplotlib" "/tmp/plot.pkl"
  in
  test_message "show_plot Python renderer uses deserialize and savefig"
    (match matplotlib_render with
     | Ok (script, script_name, runtime) ->
         script_name = "render_plot.py"
         && runtime = "Python"
         && contains script "deserialize"
         && contains script "savefig"
     | Error _ -> false);
  let seaborn_render =
    Show_plot.render_script_for_class "seaborn" "/tmp/plot.pkl"
  in
  test_message "show_plot seaborn renderer uses deserialize and savefig"
    (match seaborn_render with
     | Ok (script, script_name, runtime) ->
         script_name = "render_plot.py"
         && runtime = "Python"
         && contains script "deserialize"
         && contains script "seaborn"
         && contains script "savefig"
     | Error _ -> false);
  test_message "show_plot rejects unsupported plot classes"
    (match Show_plot.render_script_for_class "vega" "/tmp/plot.json" with
     | Error msg -> contains msg "vega" && contains msg "ggplot" && contains msg "matplotlib" && contains msg "plotnine" && contains msg "seaborn" && contains msg "plotly" && contains msg "altair"
     | Ok _ -> false);
  print_newline ();

  Printf.printf "Phase 7 — Multi-line: Parser newline tolerance:\n";
  test "list with internal newline"
    "[1,\n2,\n3]"
    "[1, 2, 3]";
  test "dict with internal newline"
    "[x: 1,\ny: 2]"
    {|{`x`: 1, `y`: 2}|};
  test "function call with newline in args"
    "add = \\(a, b) a + b\nadd(3,\n5)"
    "8";
  test "lambda params with newline"
    "f = \\(a,\nb) a * b\nf(4, 5)"
    "20";
  test "node command pipeline with indented trailing newline"
    "type(node(command = read_csv(\"data/mtcars.csv\", separator = \"|\") |>\n    mutate($cyl = factor($cyl), $am = factor($am)), serializer = ^csv))"
    {|"Node"|};
  test "node command maybe-pipeline with tab-indented trailing newline"
    "type(node(command = data ?|>\n\ttransform(data), serializer = ^csv))"
    {|"Node"|};
  print_newline ();

  Printf.printf "Phase 7 — Standard packages loaded:\n";
  (* Verify functions from all standard packages are available *)
  test "core: print available" "type(print)" {|"BuiltinFunction"|};
  test "core: type available" "type(type)" {|"BuiltinFunction"|};
  test "core: pretty_print available" "type(pretty_print)" {|"BuiltinFunction"|};
  test "stats: mean available" "type(mean)" {|"BuiltinFunction"|};
  test "stats: sd available" "type(sd)" {|"BuiltinFunction"|};
  test "colcraft: select available" "type(select)" {|"BuiltinFunction"|};
  test "colcraft: filter available" "type(filter)" {|"BuiltinFunction"|};
  test "strcraft: str_substring available" "type(str_substring)" {|"BuiltinFunction"|};
  test "math: sqrt available" "type(sqrt)" {|"BuiltinFunction"|};
  test "base: assert available" "type(assert)" {|"BuiltinFunction"|};
  test "dataframe: read_csv available" "type(read_csv)" {|"BuiltinFunction"|};
  test "dataframe: read_parquet available" "type(read_parquet)" {|"BuiltinFunction"|};
  test "pipeline: pipeline_nodes available" "type(pipeline_nodes)" {|"BuiltinFunction"|};
  test "explain: explain available" "type(explain)" {|"BuiltinFunction"|};
  test "packages: packages available" "type(packages)" {|"BuiltinFunction"|};
  test "packages: package_info available" "type(package_info)" {|"BuiltinFunction"|};
  test "help: help returns NA (proving it ran successfully)" "help('mean')" "NA";
  test "help: apropos returns NA" "apropos('mean')" "NA";
  print_newline ()
