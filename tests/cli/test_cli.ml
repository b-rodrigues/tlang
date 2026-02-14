let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Phase 7 — CLI: packages() builtin:\n";
  test "packages returns list"
    "type(packages())"
    {|"List"|};
  test "packages count"
    "length(packages())"
    "8";
  test "package_info stats"
    {|package_info("stats").name|}
    {|"stats"|};
  test "package_info stats description"
    {|package_info("stats").description|}
    {|"Statistical summaries and models"|};
  test "package_info stats functions"
    {|type(package_info("stats").functions)|}
    {|"List"|};
  test "package_info missing"
    {|package_info("nonexistent")|}
    {|Error(KeyError: "Package `nonexistent` not found.")|};
  test "package_info core"
    {|package_info("core").name|}
    {|"core"|};
  test "package_info colcraft"
    {|package_info("colcraft").name|}
    {|"colcraft"|};
  test "package_info math"
    {|package_info("math").name|}
    {|"math"|};
  test "package_info non-string"
    "package_info(42)"
    {|Error(TypeError: "Function `package_info` expects a string argument.")|};
  print_newline ();

  Printf.printf "Phase 7 — Pretty-print builtin:\n";
  test "pretty_print int"
    "pretty_print(42)"
    "null";
  test "pretty_print list"
    "pretty_print([1, 2, 3])"
    "null";
  test "pretty_print error"
    "pretty_print(1 / 0)"
    "null";
  print_newline ();

  Printf.printf "Phase 7 — Multi-line: Parser newline tolerance:\n";
  test "list with internal newline"
    "[1,\n2,\n3]"
    "[1, 2, 3]";
  test "dict with internal newline"
    "{x: 1,\ny: 2}"
    {|{`x`: 1, `y`: 2}|};
  test "function call with newline in args"
    "add = \\(a, b) a + b\nadd(3,\n5)"
    "8";
  test "lambda params with newline"
    "f = \\(a,\nb) a * b\nf(4, 5)"
    "20";
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
  test "math: sqrt available" "type(sqrt)" {|"BuiltinFunction"|};
  test "base: assert available" "type(assert)" {|"BuiltinFunction"|};
  test "dataframe: read_csv available" "type(read_csv)" {|"BuiltinFunction"|};
  test "pipeline: pipeline_nodes available" "type(pipeline_nodes)" {|"BuiltinFunction"|};
  test "explain: explain available" "type(explain)" {|"BuiltinFunction"|};
  test "packages: packages available" "type(packages)" {|"BuiltinFunction"|};
  test "packages: package_info available" "type(package_info)" {|"BuiltinFunction"|};
  print_newline ()
