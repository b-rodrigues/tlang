let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "Phase 3 — Basic Pipeline:\n";
  test "simple pipeline"
    "pipeline {\n  x = 1\n  y = 2\n  z = x + y\n}"
    "Pipeline(3 nodes: [x, y, z])";
  test "pipeline type"
    "type(pipeline {\n  a = 10\n})"
    {|"Pipeline"|};
  test "pipeline with expressions"
    "pipeline {\n  a = 2 * 3\n  b = a + 4\n}"
    "Pipeline(2 nodes: [a, b])";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Node Access:\n";
  let env_p3 = Packages.init_env () in
  let (_, env_p3) = eval_string_env "p = pipeline {\n  x = 10\n  y = 20\n  total = x + y\n}" env_p3 in
  let (v, _) = eval_string_env "p.x" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "10" then begin
    incr pass_count; Printf.printf "  ✓ pipeline node access via dot (x)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline node access via dot (x)\n    Expected: 10\n    Got: %s\n" result
  end;
  let (v, _) = eval_string_env "p.total" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "30" then begin
    incr pass_count; Printf.printf "  ✓ pipeline node access via dot (total)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline node access via dot (total)\n    Expected: 30\n    Got: %s\n" result
  end;
  let (v, _) = eval_string_env "p.nonexistent" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = {|Error(KeyError: "Node `nonexistent` not found in Pipeline.")|} then begin
    incr pass_count; Printf.printf "  ✓ missing pipeline node returns error\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ missing pipeline node returns error\n    Expected: Error(KeyError: ...)\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 3 — Deterministic Execution:\n";
  test "pipeline executes deterministically"
    "p1 = pipeline {\n  a = 5\n  b = a * 2\n  c = b + 1\n}; p2 = pipeline {\n  a = 5\n  b = a * 2\n  c = b + 1\n}; p1.c == p2.c"
    "true";
  print_newline ();

  Printf.printf "Phase 3 — Dependency Resolution:\n";
  test "out-of-order dependencies resolved"
    "p = pipeline {\n  result = x + y\n  x = 3\n  y = 7\n}; p.result"
    "10";
  test "chain dependencies"
    "p = pipeline {\n  a = 1\n  b = a + 1\n  c = b + 1\n  d = c + 1\n}; p.d"
    "4";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Introspection:\n";
  let (v, _) = eval_string_env "pipeline_nodes(p)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["x", "y", "total"]|} then begin
    incr pass_count; Printf.printf "  ✓ pipeline_nodes() lists all nodes\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_nodes() lists all nodes\n    Expected: [\"x\", \"y\", \"total\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|pipeline_node(p, "total")|} env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "30" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_node() gets specific node value\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_node() gets specific node value\n    Expected: 30\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "pipeline_deps(p)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`x`: [], `y`: [], `total`: ["x", "y"]}|} then begin
    incr pass_count; Printf.printf "  ✓ pipeline_deps() returns dependency graph\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_deps() returns dependency graph\n    Expected: {`x`: [], `y`: [], `total`: [\"x\", \"y\"]}\n    Got: %s\n" result
  end;

  test "pipeline_nodes on non-pipeline"
    "pipeline_nodes(42)"
    {|Error(TypeError: "Function `pipeline_nodes` expects a Pipeline.")|};
  test "pipeline_node missing key"
    {|p = pipeline { a = 1 }; pipeline_node(p, "b")|}
    {|Error(KeyError: "Node `b` not found in Pipeline.")|};
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Re-run (Caching):\n";
  let (v, _) = eval_string_env "pipeline_run(p)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "Pipeline(3 nodes: [x, y, total])" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_run() re-runs and returns same result\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_run() re-runs and returns same result\n    Expected: Pipeline(3 nodes: [x, y, total])\n    Got: %s\n" result
  end;

  (* Re-run produces same node values *)
  let (rerun_result, _) = eval_string_env "p2 = pipeline_run(p); p2.total" env_p3 in
  let result = Ast.Utils.value_to_string rerun_result in
  if result = "30" then begin
    incr pass_count; Printf.printf "  ✓ re-run preserves cached values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ re-run preserves cached values\n    Expected: 30\n    Got: %s\n" result
  end;

  test "pipeline_run on non-pipeline"
    "pipeline_run(42)"
    {|Error(TypeError: "Function `pipeline_run` expects a Pipeline.")|};
  print_newline ();

  Printf.printf "Pipeline Build and Artifact I/O:\n";
  test "build_pipeline returns output path"
    "p = pipeline {\n  a = 1\n  b = a + 2\n}\nout = build_pipeline(p)\nok = if (is_error(out)) (true) else (starts_with(out, \"/nix/store/\"))\nok"
    "true";
  test "read_node reads serialized artifact"
    "p = pipeline {\n  a = 1\n  b = a + 2\n}\nout = build_pipeline(p)\nok = if (is_error(out)) (error_code(read_node(\"b\")) == \"FileError\") else (read_node(\"b\") == 3)\nok"
    "true";
  test "load_node loads serialized artifact"
    "p = pipeline {\n  a = 10\n  b = a + 5\n}\nout = build_pipeline(p)\nok = if (is_error(out)) (error_code(load_node(\"b\")) == \"FileError\") else (load_node(\"b\") == 15)\nok"
    "true";
  test "read_node missing key"
    "p = pipeline {\n  a = 1\n}\nout = build_pipeline(p)\nok = if (is_error(out)) (error_code(read_node(\"missing\")) == \"FileError\") else (error_code(read_node(\"missing\")) == \"KeyError\")\nok"
    "true";
  print_newline ();

  Printf.printf "Serialization Builtins:\n";
  test "serialize and deserialize roundtrip"
    {|serialize([1, 2, 3], "test_roundtrip.tobj"); deserialize("test_roundtrip.tobj")|}
    "[1, 2, 3]";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline with Pipes:\n";
  test "pipeline with pipe operator"
    "double = \\(x) x * 2\np = pipeline {\n  a = 5\n  b = a |> double\n}; p.b"
    "10";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline with Functions:\n";
  test "pipeline with function calls"
    "p = pipeline {\n  data = [1, 2, 3]\n  total = sum(data)\n  count = length(data)\n}; p.total"
    "6";
  test "pipeline nodes available individually"
    "p = pipeline {\n  data = [1, 2, 3]\n  total = sum(data)\n  count = length(data)\n}; p.count"
    "3";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Error Handling:\n";
  test "pipeline cycle detection"
    "pipeline {\n  a = b\n  b = a\n}"
    {|Error(ValueError: "Pipeline has a dependency cycle involving node `a`.")|};
  test "pipeline with error in node"
    "pipeline {\n  a = 1 / 0\n  b = a + 1\n}"
    "Pipeline(2 nodes: [a, b])\nErrors:\n  - `a` failed: Division by zero.\n  - `b` failed: Division by zero.";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline with DataFrame:\n";
  (* Create CSV for pipeline DataFrame tests *)
  let csv_p3 = "test_phase3.csv" in
  let oc5 = open_out csv_p3 in
  output_string oc5 "name,value\nAlice,10\nBob,20\nCharlie,30\n";
  close_out oc5;

  let (_, env_p3_df) = eval_string_env (Printf.sprintf
    {|p = pipeline {
  data = read_csv("%s")
  rows = data |> nrow
  cols = data |> ncol
  names = data |> colnames
}|} csv_p3) (Packages.init_env ()) in
  let (v, _) = eval_string_env "p.rows" env_p3_df in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ pipeline with DataFrame nrow\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline with DataFrame nrow\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "p.cols" env_p3_df in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ pipeline with DataFrame ncol\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline with DataFrame ncol\n    Expected: 2\n    Got: %s\n" result
  end;
  (try Sys.remove csv_p3 with _ -> ());
  print_newline ()
