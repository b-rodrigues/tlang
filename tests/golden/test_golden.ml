(* tests/golden/test_golden.ml *)
(* Phase 8: Golden tests for pipelines *)
(* These tests verify complete pipeline outputs against expected baselines *)

let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "Phase 8 — Golden: Pipeline Baseline Outputs:\n";

  (* Golden test 1: Simple arithmetic pipeline *)
  test "golden: arithmetic pipeline"
    "p = pipeline {\n  a = 2 + 3\n  b = a * 4\n  c = b - 1\n}; p.c"
    "19";

  (* Golden test 2: Pipeline with function composition *)
  test "golden: function pipeline"
    "double = \\(x) x * 2\ninc = \\(x) x + 1\np = pipeline {\n  x = 5\n  y = x |> double\n  z = y |> inc\n}; p.z"
    "11";

  (* Golden test 3: Pipeline with list operations *)
  test "golden: list pipeline"
    "p = pipeline {\n  data = [1, 2, 3, 4, 5]\n  squares = map(data, \\(x) x * x)\n  total = sum(squares)\n  count = length(data)\n}; p.total"
    "55";

  (* Golden test 4: Pipeline node count *)
  test "golden: list pipeline count"
    "p = pipeline {\n  data = [1, 2, 3, 4, 5]\n  squares = map(data, \\(x) x * x)\n  total = sum(squares)\n  count = length(data)\n}; p.count"
    "5";

  (* Golden test 5: Pipeline representation *)
  test "golden: pipeline display format"
    "pipeline {\n  a = 1\n  b = 2\n  c = a + b\n}"
    "Pipeline(3 nodes: [a, b, c])";

  (* Golden test 6: Out-of-order dependency resolution *)
  test "golden: out-of-order deps"
    "p = pipeline {\n  sum = x + y + z\n  x = 10\n  y = 20\n  z = 30\n}; p.sum"
    "60";

  (* Golden test 7: Chained computation *)
  test "golden: chain computation"
    "p = pipeline {\n  a = 1\n  b = a + 1\n  c = b * 2\n  d = c + b\n  e = d * a\n}; p.e"
    "6";

  (* Golden test 8: Pipeline introspection - nodes *)
  test "golden: introspection nodes"
    "p = pipeline {\n  x = 1\n  y = 2\n}; pipeline_nodes(p)"
    {|["x", "y"]|};

  (* Golden test 9: Pipeline introspection - deps *)
  let env_g = Eval.initial_env () in
  let (_, env_g) = eval_string_env "p = pipeline {\n  a = 1\n  b = 2\n  c = a + b\n}" env_g in
  let (v, _) = eval_string_env "pipeline_deps(p)" env_g in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`a`: [], `b`: [], `c`: ["a", "b"]}|} then begin
    incr pass_count; Printf.printf "  ✓ golden: introspection deps\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: introspection deps\n    Expected: {`a`: [], `b`: [], `c`: [\"a\", \"b\"]}\n    Got: %s\n" result
  end;

  (* Golden test 10: Pipeline re-run preserves values *)
  let (v, _) = eval_string_env "p2 = pipeline_run(p); p2.c" env_g in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ golden: re-run preserves values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: re-run preserves values\n    Expected: 3\n    Got: %s\n" result
  end;

  (* Golden test 11: Pipeline determinism *)
  test "golden: deterministic execution"
    "p1 = pipeline {\n  a = 7\n  b = a * 3\n  c = b + 1\n}; p2 = pipeline {\n  a = 7\n  b = a * 3\n  c = b + 1\n}; p1.c == p2.c"
    "true";
  print_newline ();

  Printf.printf "Phase 8 — Golden: Pipeline Error Baselines:\n";

  (* Golden test: Cycle detection *)
  test "golden: cycle detection"
    "pipeline {\n  a = b\n  b = a\n}"
    {|Error(ValueError: "Pipeline has a dependency cycle involving node 'a'")|};

  (* Golden test: Node failure *)
  test "golden: node failure propagation"
    "pipeline {\n  a = 1 / 0\n  b = a + 1\n}"
    {|Error(ValueError: "Pipeline node 'a' failed: Error(DivisionByZero: "Division by zero")")|};

  (* Golden test: Missing node access *)
  test "golden: missing node error"
    "p = pipeline {\n  x = 42\n}; p.missing"
    {|Error(KeyError: "node 'missing' not found in Pipeline")|};

  (* Golden test: Introspection on non-pipeline *)
  test "golden: pipeline_nodes type error"
    "pipeline_nodes(42)"
    {|Error(TypeError: "pipeline_nodes() expects a Pipeline")|};

  test "golden: pipeline_run type error"
    "pipeline_run(42)"
    {|Error(TypeError: "pipeline_run() expects a Pipeline")|};

  test "golden: pipeline_node missing key"
    {|p = pipeline { a = 1 }; pipeline_node(p, "z")|}
    {|Error(KeyError: "node 'z' not found in Pipeline")|};
  print_newline ();

  Printf.printf "Phase 8 — Golden: Pipeline with Data:\n";

  (* Create CSV for golden DataFrame pipeline tests *)
  let csv_golden = "test_golden.csv" in
  let oc = open_out csv_golden in
  output_string oc "name,value,category\nAlice,100,A\nBob,200,B\nCharlie,150,A\nDiana,300,B\nEve,250,A\n";
  close_out oc;

  let env_gd = Eval.initial_env () in
  let (_, env_gd) = eval_string_env (Printf.sprintf
    {|p = pipeline {
  data = read_csv("%s")
  rows = data |> nrow
  cols = data |> ncol
  names = data |> colnames
  filtered = filter(data, \(row) row.value > 150)
  filtered_count = filtered |> nrow
}|} csv_golden) env_gd in

  let (v, _) = eval_string_env "p.rows" env_gd in
  let result = Ast.Utils.value_to_string v in
  if result = "5" then begin
    incr pass_count; Printf.printf "  ✓ golden: data pipeline nrow\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: data pipeline nrow\n    Expected: 5\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "p.cols" env_gd in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ golden: data pipeline ncol\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: data pipeline ncol\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "p.names" env_gd in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "value", "category"]|} then begin
    incr pass_count; Printf.printf "  ✓ golden: data pipeline colnames\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: data pipeline colnames\n    Expected: [\"name\", \"value\", \"category\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "p.filtered_count" env_gd in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ golden: data pipeline filtered count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: data pipeline filtered count\n    Expected: 3\n    Got: %s\n" result
  end;

  (try Sys.remove csv_golden with _ -> ());
  print_newline ()
