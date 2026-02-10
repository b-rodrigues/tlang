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
  print_newline ();

  (* ===================================================================== *)
  (* Window Function Golden Tests                                          *)
  (* Expected values below are computed from R/dplyr for the simple.csv    *)
  (* dataset: age = [25, 30, 35, 28, 22, 45, 33, 29, 31, 27]             *)
  (*          score = [85.5, 92.3, 78.9, 88.1, 95.0, 82.4, 90.2, 76.5,   *)
  (*                   89.3, 91.7]                                         *)
  (* ===================================================================== *)

  Printf.printf "Phase 8 — Golden: Window Functions vs dplyr:\n";

  (* --- Ranking functions --- *)

  (* R: dplyr::row_number(c(25, 30, 35, 28, 22, 45, 33, 29, 31, 27))
     =>  2, 6, 9, 4, 1, 10, 8, 5, 7, 3 *)
  test "golden window: row_number matches dplyr"
    {|row_number([25, 30, 35, 28, 22, 45, 33, 29, 31, 27])|}
    "Vector[2, 6, 9, 4, 1, 10, 8, 5, 7, 3]";

  (* R: dplyr::min_rank(c(25, 30, 35, 28, 22, 45, 33, 29, 31, 27))
     =>  2, 6, 9, 4, 1, 10, 8, 5, 7, 3 (no ties in this data) *)
  test "golden window: min_rank matches dplyr"
    {|min_rank([25, 30, 35, 28, 22, 45, 33, 29, 31, 27])|}
    "Vector[2, 6, 9, 4, 1, 10, 8, 5, 7, 3]";

  (* R: dplyr::dense_rank(c(25, 30, 35, 28, 22, 45, 33, 29, 31, 27))
     =>  2, 6, 9, 4, 1, 10, 8, 5, 7, 3 (no ties in this data) *)
  test "golden window: dense_rank matches dplyr"
    {|dense_rank([25, 30, 35, 28, 22, 45, 33, 29, 31, 27])|}
    "Vector[2, 6, 9, 4, 1, 10, 8, 5, 7, 3]";

  (* R: dplyr::min_rank(c(1, 1, 2, 2, 2))
     =>  1, 1, 3, 3, 3 *)
  test "golden window: min_rank with ties matches dplyr"
    {|min_rank([1, 1, 2, 2, 2])|}
    "Vector[1, 1, 3, 3, 3]";

  (* R: dplyr::dense_rank(c(1, 1, 2, 2, 2))
     =>  1, 1, 2, 2, 2 *)
  test "golden window: dense_rank with ties matches dplyr"
    {|dense_rank([1, 1, 2, 2, 2])|}
    "Vector[1, 1, 2, 2, 2]";

  (* R: dplyr::percent_rank(c(25, 30, 35, 28, 22, 45, 33, 29, 31, 27))
     => (rank-1)/(n-1) for n=10
     Ranks: 2,6,9,4,1,10,8,5,7,3
     => 1/9, 5/9, 8/9, 3/9, 0/9, 9/9, 7/9, 4/9, 6/9, 2/9 *)
  test "golden window: percent_rank matches dplyr"
    {|percent_rank([1, 2, 3, 4, 5])|}
    "Vector[0., 0.25, 0.5, 0.75, 1.]";

  (* R: dplyr::cume_dist(c(1, 2, 3, 4, 5))
     => 0.2, 0.4, 0.6, 0.8, 1.0 *)
  test "golden window: cume_dist matches dplyr"
    {|cume_dist([1, 2, 3, 4, 5])|}
    "Vector[0.2, 0.4, 0.6, 0.8, 1.]";

  (* R: dplyr::cume_dist(c(1, 1, 2, 2, 2))
     => 0.4, 0.4, 1.0, 1.0, 1.0 *)
  test "golden window: cume_dist with ties matches dplyr"
    {|cume_dist([1, 1, 2, 2, 2])|}
    "Vector[0.4, 0.4, 1., 1., 1.]";

  (* R: dplyr::ntile(c(1, 2, 3, 4), 2)
     => 1, 1, 2, 2 *)
  test "golden window: ntile matches dplyr"
    {|ntile([1, 2, 3, 4], 2)|}
    "Vector[1, 1, 2, 2]";

  (* --- Offset functions --- *)

  (* R: dplyr::lag(c(85.5, 92.3, 78.9, 88.1, 95.0))
     => NA, 85.5, 92.3, 78.9, 88.1 *)
  test "golden window: lag matches dplyr"
    {|lag([85.5, 92.3, 78.9, 88.1, 95.0])|}
    "Vector[NA, 85.5, 92.3, 78.9, 88.1]";

  (* R: dplyr::lead(c(85.5, 92.3, 78.9, 88.1, 95.0))
     => 92.3, 78.9, 88.1, 95.0, NA *)
  test "golden window: lead matches dplyr"
    {|lead([85.5, 92.3, 78.9, 88.1, 95.0])|}
    "Vector[92.3, 78.9, 88.1, 95.0, NA]";

  (* R: dplyr::lag(c(1, 2, 3, 4, 5), 2)
     => NA, NA, 1, 2, 3 *)
  test "golden window: lag with offset 2 matches dplyr"
    {|lag([1, 2, 3, 4, 5], 2)|}
    "Vector[NA, NA, 1, 2, 3]";

  (* R: dplyr::lead(c(1, 2, 3, 4, 5), 2)
     => 3, 4, 5, NA, NA *)
  test "golden window: lead with offset 2 matches dplyr"
    {|lead([1, 2, 3, 4, 5], 2)|}
    "Vector[3, 4, 5, NA, NA]";

  (* --- Cumulative functions --- *)

  (* R: cumsum(c(1, 2, 3, 4, 5))
     => 1, 3, 6, 10, 15 *)
  test "golden window: cumsum matches R"
    {|cumsum([1, 2, 3, 4, 5])|}
    "Vector[1, 3, 6, 10, 15]";

  (* R: cumsum(c(85.5, 92.3, 78.9, 88.1, 95.0))
     => 85.5, 177.8, 256.7, 344.8, 439.8 *)
  test "golden window: cumsum float matches R"
    {|cumsum([85.5, 92.3, 78.9, 88.1, 95.0])|}
    "Vector[85.5, 177.8, 256.7, 344.8, 439.8]";

  (* R: cummin(c(3, 1, 4, 1, 5))
     => 3, 1, 1, 1, 1 *)
  test "golden window: cummin matches R"
    {|cummin([3, 1, 4, 1, 5])|}
    "Vector[3, 1, 1, 1, 1]";

  (* R: cummax(c(1, 3, 2, 5, 4))
     => 1, 3, 3, 5, 5 *)
  test "golden window: cummax matches R"
    {|cummax([1, 3, 2, 5, 4])|}
    "Vector[1, 3, 3, 5, 5]";

  (* R: dplyr::cummean(c(1, 2, 3, 4))
     => 1.0, 1.5, 2.0, 2.5 *)
  test "golden window: cummean matches dplyr"
    {|cummean([1, 2, 3, 4])|}
    "Vector[1., 1.5, 2., 2.5]";

  (* R: dplyr::cumall(c(TRUE, TRUE, FALSE, TRUE))
     => TRUE, TRUE, FALSE, FALSE *)
  test "golden window: cumall matches dplyr"
    {|cumall([true, true, false, true])|}
    "Vector[true, true, false, false]";

  (* R: dplyr::cumany(c(FALSE, FALSE, TRUE, FALSE))
     => FALSE, FALSE, TRUE, TRUE *)
  test "golden window: cumany matches dplyr"
    {|cumany([false, false, true, false])|}
    "Vector[false, false, true, true]";

  print_newline ()
