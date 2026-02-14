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
    "double = \\(n) n * 2\ninc = \\(m) m + 1\np = pipeline {\n  x = 5\n  y = x |> double\n  z = y |> inc\n}; p.z"
    "11";

  (* Golden test 3: Pipeline with list operations *)
  test "golden: list pipeline"
    "p = pipeline {\n  data = [1, 2, 3, 4, 5]\n  squares = map(data, \\(n) n * n)\n  total = sum(squares)\n  count = length(data)\n}; p.total"
    "55";

  (* Golden test 4: Pipeline node count *)
  test "golden: list pipeline count"
    "p = pipeline {\n  data = [1, 2, 3, 4, 5]\n  squares = map(data, \\(n) n * n)\n  total = sum(squares)\n  count = length(data)\n}; p.count"
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
    {|Error(ValueError: "Pipeline has a dependency cycle involving node `a`.")|};

  (* Golden test: Node failure *)
  test "golden: node failure propagation"
    "pipeline {\n  a = 1 / 0\n  b = a + 1\n}"
    {|Error(ValueError: "Pipeline node `a` failed: Error(DivisionByZero: "Division by zero.")")|};

  (* Golden test: Missing node access *)
  test "golden: missing node error"
    "p = pipeline {\n  x = 42\n}; p.missing"
    {|Error(KeyError: "Node `missing` not found in Pipeline.")|};

  (* Golden test: Introspection on non-pipeline *)
  test "golden: pipeline_nodes type error"
    "pipeline_nodes(42)"
    {|Error(TypeError: "Function `pipeline_nodes` expects a Pipeline.")|};

  test "golden: pipeline_run type error"
    "pipeline_run(42)"
    {|Error(TypeError: "Function `pipeline_run` expects a Pipeline.")|};

  test "golden: pipeline_node missing key"
    {|p = pipeline { a = 1 }; pipeline_node(p, "z")|}
    {|Error(KeyError: "Node `z` not found in Pipeline.")|};
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
  filtered = filter(data, $value > 150)
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
  (* Phase 5: CSV Read/Write Options Golden Tests                           *)
  (* ===================================================================== *)

  Printf.printf "Phase 5 — Golden: CSV Read/Write Options:\n";

  (* Create test CSV with comma separator *)
  let csv_golden_rw = "test_golden_rw.csv" in
  let oc = open_out csv_golden_rw in
  output_string oc "name,value\nAlice,100\nBob,200\nCharlie,150\n";
  close_out oc;

  (* Test: read_csv -> write_csv -> read_csv roundtrip *)
  let env_rw = Eval.initial_env () in
  let (_, env_rw) = eval_string_env (Printf.sprintf
    {|df = read_csv("%s")|} csv_golden_rw) env_rw in
  let csv_golden_out = "test_golden_rw_out.csv" in
  let (_, env_rw) = eval_string_env (Printf.sprintf
    {|write_csv(df, "%s")|} csv_golden_out) env_rw in
  let (_, env_rw) = eval_string_env (Printf.sprintf
    {|df2 = read_csv("%s")|} csv_golden_out) env_rw in
  let (v, _) = eval_string_env "nrow(df2)" env_rw in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ golden: read->write->read roundtrip preserves rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: read->write->read roundtrip preserves rows\n    Expected: 3\n    Got: %s\n" result
  end;
  let (v, _) = eval_string_env "colnames(df2)" env_rw in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "value"]|} then begin
    incr pass_count; Printf.printf "  ✓ golden: read->write->read roundtrip preserves columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: read->write->read roundtrip preserves columns\n    Expected: [\"name\", \"value\"]\n    Got: %s\n" result
  end;

  (* Test: write_csv with custom separator and read back *)
  let csv_golden_sep_out = "test_golden_sep_out.csv" in
  let (_, env_rw) = eval_string_env (Printf.sprintf
    {|write_csv(df, "%s", separator = ";")|} csv_golden_sep_out) env_rw in
  let (_, env_rw) = eval_string_env (Printf.sprintf
    {|df3 = read_csv("%s", separator = ";")|} csv_golden_sep_out) env_rw in
  let (v, _) = eval_string_env "nrow(df3)" env_rw in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ golden: write separator=\";\" -> read separator=\";\" roundtrip preserves rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: write separator=\";\" -> read separator=\";\" roundtrip preserves rows\n    Expected: 3\n    Got: %s\n" result
  end;
  let (v, _) = eval_string_env "colnames(df3)" env_rw in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "value"]|} then begin
    incr pass_count; Printf.printf "  ✓ golden: write separator=\";\" -> read separator=\";\" roundtrip preserves columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: write separator=\";\" -> read separator=\";\" roundtrip preserves columns\n    Expected: [\"name\", \"value\"]\n    Got: %s\n" result
  end;

  (* Test: write empty DataFrame *)
  let csv_golden_empty = "test_golden_empty_rw.csv" in
  let env_empty = Eval.initial_env () in
  let (_, env_empty) = eval_string_env (Printf.sprintf
    {|df = read_csv("%s")|} csv_golden_rw) env_empty in
  let (_, env_empty) = eval_string_env
    {|empty_df = filter(df, $value > 9999)|} env_empty in
  let (_, env_empty) = eval_string_env (Printf.sprintf
    {|write_csv(empty_df, "%s")|} csv_golden_empty) env_empty in
  let (_, env_empty) = eval_string_env (Printf.sprintf
    {|df_back = read_csv("%s")|} csv_golden_empty) env_empty in
  let (v, _) = eval_string_env "nrow(df_back)" env_empty in
  let result = Ast.Utils.value_to_string v in
  if result = "0" then begin
    incr pass_count; Printf.printf "  ✓ golden: write empty DataFrame roundtrip\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: write empty DataFrame roundtrip\n    Expected: 0\n    Got: %s\n" result
  end;

  (* Test: write DataFrame with NA values *)
  let csv_golden_na = "test_golden_na_rw.csv" in
  let csv_golden_na_src = "test_golden_na_src.csv" in
  let oc = open_out csv_golden_na_src in
  output_string oc "x,y\n1,hello\nNA,world\n3,NA\n";
  close_out oc;
  let env_na = Eval.initial_env () in
  let (_, env_na) = eval_string_env (Printf.sprintf
    {|df = read_csv("%s")|} csv_golden_na_src) env_na in
  let (_, env_na) = eval_string_env (Printf.sprintf
    {|write_csv(df, "%s")|} csv_golden_na) env_na in
  let (_, env_na) = eval_string_env (Printf.sprintf
    {|df2 = read_csv("%s")|} csv_golden_na) env_na in
  let (v, _) = eval_string_env "nrow(df2)" env_na in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ golden: write NA DataFrame roundtrip preserves rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ golden: write NA DataFrame roundtrip preserves rows\n    Expected: 3\n    Got: %s\n" result
  end;

  (* Clean up roundtrip test files *)
  (try Sys.remove csv_golden_rw with _ -> ());
  (try Sys.remove csv_golden_out with _ -> ());
  (try Sys.remove csv_golden_sep_out with _ -> ());
  (try Sys.remove csv_golden_empty with _ -> ());
  (try Sys.remove csv_golden_na with _ -> ());
  (try Sys.remove csv_golden_na_src with _ -> ());
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
    "Vector[92.3, 78.9, 88.1, 95., NA]";

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

  print_newline ();

  (* ===================================================================== *)
  (* Window Functions NA Handling Golden Tests                               *)
  (* Expected values match R's dplyr behavior for NA in window functions     *)
  (* ===================================================================== *)

  Printf.printf "Phase 8 — Golden: Window Functions NA Handling:\n";

  (* R: dplyr::row_number(c(3, NA, 1)) => 2, NA, 1 *)
  test "golden window NA: row_number with NA"
    {|row_number([3, NA, 1])|}
    "Vector[2, NA(Int), 1]";

  (* R: dplyr::min_rank(c(3, NA, 1, 3)) => 2, NA, 1, 2 *)
  test "golden window NA: min_rank with NA"
    {|min_rank([3, NA, 1, 3])|}
    "Vector[2, NA(Int), 1, 2]";

  (* R: dplyr::dense_rank(c(3, NA, 1, 3)) => 2, NA, 1, 2 *)
  test "golden window NA: dense_rank with NA"
    {|dense_rank([3, NA, 1, 3])|}
    "Vector[2, NA(Int), 1, 2]";

  (* R: dplyr::ntile(c(10, NA, 20, NA, 30), 2) => 1, NA, 1, NA, 2 *)
  test "golden window NA: ntile with NA"
    {|ntile([10, NA, 20, NA, 30], 2)|}
    "Vector[1, NA(Int), 1, NA(Int), 2]";

  (* R: dplyr::lag(c(1, NA, 3)) => NA, 1, NA *)
  test "golden window NA: lag propagates NA"
    {|lag([1, NA, 3])|}
    "Vector[NA, 1, NA]";

  (* R: dplyr::lead(c(1, NA, 3)) => NA, 3, NA *)
  test "golden window NA: lead propagates NA"
    {|lead([1, NA, 3])|}
    "Vector[NA, 3, NA]";

  (* R: cumsum(c(1, NA, 3)) => 1, NA, NA *)
  test "golden window NA: cumsum propagates NA"
    {|cumsum([1, NA, 3])|}
    "Vector[1, NA(Float), NA(Float)]";

  (* R: cummin(c(3, NA, 1)) => 3, NA, NA *)
  test "golden window NA: cummin propagates NA"
    {|cummin([3, NA, 1])|}
    "Vector[3, NA(Float), NA(Float)]";

  (* R: cummax(c(1, NA, 5)) => 1, NA, NA *)
  test "golden window NA: cummax propagates NA"
    {|cummax([1, NA, 5])|}
    "Vector[1, NA(Float), NA(Float)]";

  (* R: dplyr::cummean(c(2, NA, 6)) => 2, NA, NA *)
  test "golden window NA: cummean propagates NA"
    {|cummean([2, NA, 6])|}
    "Vector[2., NA(Float), NA(Float)]";

  print_newline ();

  (* ===================================================================== *)
  (* NA Parameter Support Golden Tests                                      *)
  (* Expected values below are computed from R for na_rm parameter handling *)
  (* ===================================================================== *)

  Printf.printf "Phase 8 — Golden: NA Parameter Support (na_rm):\n";

  (* --- mean() na_rm --- *)

  (* R: mean(c(1, NA, 3), na.rm = TRUE) => 2 *)
  test "golden na_rm: mean na_rm=true"
    {|mean([1, NA, 3], na_rm = true)|}
    "2.";

  (* R: mean(c(NA, NA, NA), na.rm = TRUE) => NaN — T returns NA(Float) *)
  test "golden na_rm: mean all NA na_rm=true"
    {|mean([NA, NA, NA], na_rm = true)|}
    "NA(Float)";

  (* R: mean(c(1, 2, 3), na.rm = TRUE) => 2 *)
  test "golden na_rm: mean no NAs na_rm=true"
    {|mean([1, 2, 3], na_rm = true)|}
    "2.";

  (* --- sum() na_rm --- *)

  (* R: sum(c(1, NA, 3), na.rm = TRUE) => 4 *)
  test "golden na_rm: sum na_rm=true"
    {|sum([1, NA, 3], na_rm = true)|}
    "4";

  (* R: sum(c(NA, NA, NA), na.rm = TRUE) => 0 *)
  test "golden na_rm: sum all NA na_rm=true"
    {|sum([NA, NA, NA], na_rm = true)|}
    "0";

  (* R: sum(c(1.5, NA, 2.5), na.rm = TRUE) => 4 *)
  test "golden na_rm: sum float na_rm=true"
    {|sum([1.5, NA, 2.5], na_rm = true)|}
    "4.";

  (* --- sd() na_rm --- *)

  (* R: sd(c(2, 4, NA, 4, 5, 5, NA, 9), na.rm = TRUE)
     => sd(c(2, 4, 4, 5, 5, 9)) = 2.316610 *)
  test "golden na_rm: sd na_rm=true"
    {|sd([2, 4, NA, 4, 5, 5, NA, 9], na_rm = true)|}
    "2.31660671385";

  (* R: sd(c(NA, NA, NA), na.rm = TRUE) => NA *)
  test "golden na_rm: sd all NA na_rm=true"
    {|sd([NA, NA, NA], na_rm = true)|}
    "NA(Float)";

  (* --- quantile() na_rm --- *)

  (* R: quantile(c(1, NA, 3, NA, 5), 0.5, na.rm = TRUE) => 3 *)
  test "golden na_rm: quantile na_rm=true"
    {|quantile([1, NA, 3, NA, 5], 0.5, na_rm = true)|}
    "3.";

  (* R: quantile(c(NA, NA, NA), 0.5, na.rm = TRUE) => NA *)
  test "golden na_rm: quantile all NA na_rm=true"
    {|quantile([NA, NA, NA], 0.5, na_rm = true)|}
    "NA(Float)";

  (* --- cor() na_rm --- *)

  (* R: cor(c(1, NA, 3, 4, 5), c(2, 4, NA, 8, 10), use = "pairwise.complete.obs") => 1 *)
  test "golden na_rm: cor na_rm=true pairwise"
    {|cor([1, NA, 3, 4, 5], [2, 4, NA, 8, 10], na_rm = true)|}
    "1.";

  (* R: cor(c(NA, NA, NA), c(NA, NA, NA), use = "pairwise.complete.obs") => NA *)
  test "golden na_rm: cor all NA na_rm=true"
    {|cor([NA, NA, NA], [NA, NA, NA], na_rm = true)|}
    "NA(Float)";

  (* --- Error cases: na_rm=false (default) should error on NA --- *)

  test "golden na_rm: mean default errors on NA"
    {|mean([1, NA, 3])|}
    {|Error(TypeError: "Function `mean` encountered NA value. Handle missingness explicitly.")|};

  test "golden na_rm: sum default errors on NA"
    {|sum([1, NA, 3])|}
    {|Error(TypeError: "Function `sum` encountered NA value. Handle missingness explicitly.")|};

  test "golden na_rm: sd default errors on NA"
    {|sd([1, NA, 3])|}
    {|Error(TypeError: "Function `sd` encountered NA value. Handle missingness explicitly.")|};

  test "golden na_rm: quantile default errors on NA"
    {|quantile([1, NA, 3], 0.5)|}
    {|Error(TypeError: "Function `quantile` encountered NA value. Handle missingness explicitly.")|};

  test "golden na_rm: cor default errors on NA"
    {|cor([1, NA, 3], [4, 5, 6])|}
    {|Error(TypeError: "Function `cor` encountered NA value. Handle missingness explicitly.")|};

  print_newline ()
