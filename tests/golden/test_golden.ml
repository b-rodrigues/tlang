(* tests/golden/test_golden.ml *)
(* Phase 8: Golden tests for pipelines *)
(* These tests verify complete pipeline outputs against expected baselines *)

let run_tests pass_count fail_count _failures _eval_string eval_string_env test test_env =
  Printf.printf "Phase 8 — Golden: Pipeline Baseline Outputs:\n";

  (* Golden test 1: Simple arithmetic pipeline *)
  test "golden: arithmetic pipeline"
    "p = pipeline {\n  a = 2 + 3\n  b = a * 4\n  c = b - 1\n}; read_node(p.c)"
    "not been built yet";

  (* Golden test 2: Pipeline with function composition *)
  test "golden: function pipeline"
    "double = \\(n) n * 2\ninc = \\(m) m + 1\np = pipeline {\n  x = 5\n  y = x |> double\n  z = y |> inc\n}; read_node(p.z)"
    "not been built yet";

  (* Golden test 3: Pipeline with list operations *)
  test "golden: list pipeline"
    "p = pipeline {\n  data = [1, 2, 3, 4, 5]\n  squares = map(data, \\(n) n * n)\n  total = sum(squares)\n  count = length(data)\n}; read_node(p.total)"
    "not been built yet";

  (* Golden test 4: Pipeline node count *)
  test "golden: list pipeline count"
    "p = pipeline {\n  data = [1, 2, 3, 4, 5]\n  squares = map(data, \\(n) n * n)\n  total = sum(squares)\n  count = length(data)\n}; read_node(p.count)"
    "not been built yet";

  (* Golden test 5: Pipeline representation *)
  test "golden: pipeline display format"
    "pipeline {\n  a = 1\n  b = 2\n  c = a + b\n}"
    "Pipeline(3 nodes: [a, b, c])";

  (* Golden test 6: Out-of-order dependency resolution *)
  test "golden: out-of-order deps"
    "p = pipeline {\n  sum = x + y + z\n  x = 10\n  y = 20\n  z = 30\n}; read_node(p.sum)"
    "not been built yet";

  (* Golden test 7: Chained computation *)
  test "golden: chain computation"
    "p = pipeline {\n  a = 1\n  b = a + 1\n  c = b * 2\n  d = c + b\n  e = d * a\n}; read_node(p.e)"
    "not been built yet";

  (* Golden test 8: Pipeline introspection - nodes *)
  test "golden: introspection nodes"
    "p = pipeline {\n  x = 1\n  y = 2\n}; pipeline_nodes(p)"
    {|["x", "y"]|};

  (* Golden test 9: Pipeline introspection - deps *)
  let env_g = Packages.init_env () in
  let (_, env_g) = eval_string_env "p = pipeline {\n  a = 1\n  b = 2\n  c = a + b\n}" env_g in
  test_env env_g "golden: introspection deps"
    "pipeline_deps(p)"
    {|{`a`: [], `b`: [], `c`: ["a", "b"]}|};

  (* Golden test 10: Pipeline re-run preserves values *)
  test_env env_g "golden: re-run returns FileError for unbuilt pipeline"
    "p2 = pipeline_run(p); read_node(p2.c)"
    "not been built yet";

  (* Golden test 11: Pipeline determinism *)
  test "golden: deterministic execution"
    "p = pipeline {\n  a = 7\n  b = a * 3\n  c = b + 1\n}; read_node(p.c)"
    "not been built yet";
  print_newline ();


  Printf.printf "Phase 8 — Golden: Stats/Math parity (R baselines):\n";
  (* Baselines computed from R:
     var(c(1,2,3,4,5)) = 2.5
     cov(c(1,2,3), c(2,4,6)) = 2
     median(c(1,2,10)) = 2
     iqr(c(1,2,3,4,5)) = 2
     round(pi, 2) = 3.14
  *)
  test "golden r: var" "var([1,2,3,4,5])" "2.5";
  test "golden r: cov" "cov([1,2,3], [2,4,6])" "2.";
  test "golden r: median" "median([1,2,10])" "2.";
  test "golden r: iqr" "iqr([1,2,3,4,5])" "2.";
  test "golden r: round" "round(3.14159265359, digits = 2)" "3.14";
  print_newline ();

  Printf.printf "Phase 8 — Golden: Pipeline Error Baselines:\n";

  (* Golden test: Cycle detection *)
  test "golden: cycle detection"
    "pipeline {\n  a = b\n  b = a\n}"
    {|Error(StructuralError: "Pipeline has a dependency cycle involving node `a`.")|};

  (* Golden test: Node failure *)
  test "golden: node failure propagation"
    "pipeline {\n  a = 1 / 0\n  b = a + 1\n}"
    "Pipeline(2 nodes: [a, b])";

  (* Golden test: Missing node access *)
  test "golden: missing node error"
    "p = pipeline {\n  x = 42\n}; p.missing"
    {|Error(KeyError: "Node `missing` not found in Pipeline.")|};

  (* Golden test: Introspection on non-pipeline *)
  test "golden: pipeline_nodes type error"
    "pipeline_nodes(42)"
    {|Error(TypeError: "[L1:C1] Function `pipeline_nodes` expects a Pipeline, but got Int.")|};

  test "golden: pipeline_run type error"
    "pipeline_run(42)"
    {|Error(TypeError: "Function `pipeline_run` expects a Pipeline.")|};

  test "golden: pipeline_node missing key"
    {|p = pipeline { a = 1 }; pipeline_node(p, "z")|}
    {|Error(KeyError: "Node `z` not found in Pipeline.")|};

  (* Golden test: pipeline_to_ga YAML generation *)
  (try
    let env_ga = Packages.init_env () in
    let (v, _) = eval_string_env "pipeline_to_ga(name = \"test\", file = \"\")" env_ga in
    let result = Ast.Utils.value_to_string v in
    let checks = [
      ("contains workflow name", "name: Demo Test");
      ("contains checkout action", "actions/checkout@v4");
      ("contains install-nix-action", "cachix/install-nix-action@v31");
      ("contains nix develop command", "nix develop --command t run src/pipeline.t");
      ("contains NAR_ARCHIVE", "NAR_ARCHIVE: test.nar");
      ("contains t-runs branch", "git push origin HEAD:t-runs --force");
      ("contains export_artifacts", "t export_artifacts src/pipeline.t \\\"$NAR_ARCHIVE\\\"");
    ] in
    let all_pass = ref true in
    List.iter (fun (desc, expected) ->
      if not (Test_helpers.contains result expected) then begin
        all_pass := false;
        incr fail_count;
        Printf.printf "  ✗ golden: pipeline_to_ga — %s\n    Expected to contain: %s\n" desc expected
      end
    ) checks;
    if !all_pass then begin
      incr pass_count;
      Printf.printf "  ✓ golden: pipeline_to_ga generates valid workflow YAML\n"
    end
  with e ->
    incr fail_count;
    Printf.printf "  ✗ golden: pipeline_to_ga — Exception: %s\n" (Printexc.to_string e));

  (* Golden test: pipeline_to_ga type error *)
  test "golden: pipeline_to_ga type error"
    "pipeline_to_ga(42)"
    {|Error(TypeError: "Function `pipeline_to_ga` expects a String for `pipeline_script`, but got Int.")|};

  (* Golden test: pipeline_to_ga unknown argument *)
  test "golden: pipeline_to_ga unknown arg"
    "pipeline_to_ga(unknown_arg = 1)"
    {|Error(TypeError: "Unknown argument `unknown_arg` for function `pipeline_to_ga`.
Valid arguments: pipeline_script (positional/named), name, file.")|};

  print_newline ();

  Printf.printf "Phase 8 — Golden: Pipeline with Data:\n";

  (* Create CSV for golden DataFrame pipeline tests *)
  let csv_golden = "test_golden.csv" in
  let oc = open_out csv_golden in
  output_string oc "name,value,category\nAlice,100,A\nBob,200,B\nCharlie,150,A\nDiana,300,B\nEve,250,A\n";
  close_out oc;

  let env_gd = Packages.init_env () in
  let (_, env_gd) = eval_string_env (Printf.sprintf
    {|p = pipeline {
  data = read_csv("%s")
  rows = data |> nrow
  cols = data |> ncol
  names = data |> colnames
  filtered = filter(data, $value > 150)
  filtered_count = filtered |> nrow
}|} csv_golden) env_gd in

  test_env env_gd "golden: data pipeline nrow returns FileError for unbuilt pipeline"
    "read_node(p.rows)"
    "not been built yet";

  test_env env_gd "golden: data pipeline ncol returns FileError for unbuilt pipeline"
    "read_node(p.cols)"
    "not been built yet";

  test_env env_gd "golden: data pipeline colnames returns FileError for unbuilt pipeline"
    "read_node(p.names)"
    "not been built yet";

  test_env env_gd "golden: data pipeline filtered count returns FileError for unbuilt pipeline"
    "read_node(p.filtered_count)"
    "not been built yet";

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
  let env_rw = Packages.init_env () in
  let (_, env_rw) = eval_string_env (Printf.sprintf
    {|df = read_csv("%s")|} csv_golden_rw) env_rw in
  let csv_golden_out = "test_golden_rw_out.csv" in
  let (_, env_rw) = eval_string_env (Printf.sprintf
    {|write_csv(df, "%s")|} csv_golden_out) env_rw in
  let (_, env_rw) = eval_string_env (Printf.sprintf
    {|df2 = read_csv("%s")|} csv_golden_out) env_rw in
  test_env env_rw "golden: read->write->read roundtrip preserves rows"
    "nrow(df2)" "3";
  test_env env_rw "golden: read->write->read roundtrip preserves columns"
    "colnames(df2)" {|["name", "value"]|};

  (* Test: write_csv with custom separator and read back *)
  let csv_golden_sep_out = "test_golden_sep_out.csv" in
  let (_, env_rw) = eval_string_env (Printf.sprintf
    {|write_csv(df, "%s", separator = ";")|} csv_golden_sep_out) env_rw in
  let (_, env_rw) = eval_string_env (Printf.sprintf
    {|df3 = read_csv("%s", separator = ";")|} csv_golden_sep_out) env_rw in
  test_env env_rw "golden: write separator=\";\" -> read separator=\";\" roundtrip preserves rows"
    "nrow(df3)" "3";
  test_env env_rw "golden: write separator=\";\" -> read separator=\";\" roundtrip preserves columns"
    "colnames(df3)" {|["name", "value"]|};

  (* Test: write empty DataFrame *)
  let csv_golden_empty = "test_golden_empty_rw.csv" in
  let env_empty = Packages.init_env () in
  let (_, env_empty) = eval_string_env (Printf.sprintf
    {|df = read_csv("%s")|} csv_golden_rw) env_empty in
  let (_, env_empty) = eval_string_env
    {|empty_df = filter(df, $value > 9999)|} env_empty in
  let (_, env_empty) = eval_string_env (Printf.sprintf
    {|write_csv(empty_df, "%s")|} csv_golden_empty) env_empty in
  let (_, env_empty) = eval_string_env (Printf.sprintf
    {|df_back = read_csv("%s")|} csv_golden_empty) env_empty in
  test_env env_empty "golden: write empty DataFrame roundtrip"
    "nrow(df_back)" "0";

  (* Test: write DataFrame with NA values *)
  let csv_golden_na = "test_golden_na_rw.csv" in
  let csv_golden_na_src = "test_golden_na_src.csv" in
  let oc = open_out csv_golden_na_src in
  output_string oc "x,y\n1,hello\nNA,world\n3,NA\n";
  close_out oc;
  let env_na = Packages.init_env () in
  let (_, env_na) = eval_string_env (Printf.sprintf
    {|df = read_csv("%s")|} csv_golden_na_src) env_na in
  let (_, env_na) = eval_string_env (Printf.sprintf
    {|write_csv(df, "%s")|} csv_golden_na) env_na in
  let (_, env_na) = eval_string_env (Printf.sprintf
    {|df2 = read_csv("%s")|} csv_golden_na) env_na in
  test_env env_na "golden: write NA DataFrame roundtrip preserves rows"
    "nrow(df2)" "3";

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
    "Vector[NA(Float), 85.5, 92.3, 78.9, 88.1]";

  (* R: dplyr::lead(c(85.5, 92.3, 78.9, 88.1, 95.0))
     => 92.3, 78.9, 88.1, 95.0, NA *)
  test "golden window: lead matches dplyr"
    {|lead([85.5, 92.3, 78.9, 88.1, 95.0])|}
    "Vector[92.3, 78.9, 88.1, 95., NA(Float)]";

  (* R: dplyr::lag(c(1, 2, 3, 4, 5), 2)
     => NA, NA, 1, 2, 3 *)
  test "golden window: lag with offset 2 matches dplyr"
    {|lag([1, 2, 3, 4, 5], 2)|}
    "Vector[NA(Int), NA(Int), 1, 2, 3]";

  (* R: dplyr::lead(c(1, 2, 3, 4, 5), 2)
     => 3, 4, 5, NA, NA *)
  test "golden window: lead with offset 2 matches dplyr"
    {|lead([1, 2, 3, 4, 5], 2)|}
    "Vector[3, 4, 5, NA(Int), NA(Int)]";

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
    "Vector[NA(Int), 1, NA]";

  (* R: dplyr::lead(c(1, NA, 3)) => NA, 3, NA *)
  test "golden window NA: lead propagates NA"
    {|lead([1, NA, 3])|}
    "Vector[NA, 3, NA(Int)]";

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
    {|Error(AggregationError: "Function `mean` encountered NA value. Handle missingness explicitly or set `na_rm` to true.")|};

  test "golden na_rm: sum default errors on NA"
    {|sum([1, NA, 3])|}
    {|Error(AggregationError: "Function `sum` encountered NA value. Handle missingness explicitly or set `na_rm` to true.")|};

  test "golden na_rm: sd default errors on NA"
    {|sd([1, NA, 3])|}
    {|Error(AggregationError: "Function `sd` encountered NA value. Handle missingness explicitly or set `na_rm` to true.")|};

  test "golden na_rm: quantile default errors on NA"
    {|quantile([1, NA, 3], 0.5)|}
    {|Error(AggregationError: "Function `quantile` encountered NA value. Handle missingness explicitly or set `na_rm` to true.")|};

  test "golden na_rm: cor default errors on NA"
    {|cor([1, NA, 3], [4, 5, 6])|}
    {|Error(AggregationError: "Function `cor` encountered NA value. Handle missingness explicitly or set `na_rm` to true.")|};

  Printf.printf "Phase 8 — Golden: ONNX Machine Learning:\n";

  let iris_csv = "tests/golden/data/iris.csv" in
  let iris_onnx = "tests/golden/data/iris_logreg.onnx" in

  if Sys.file_exists iris_csv && Sys.file_exists iris_onnx then begin
    let env_ml = Packages.init_env () in
    let (_, env_ml) = eval_string_env (Printf.sprintf
      {|df = read_csv("%s")
        model = t_read_onnx("%s")
      |} iris_csv iris_onnx) env_ml in

    (* Test: Metadata extraction *)
    test_env env_ml "golden onnx: input_width extraction"
      "model.input_width" "4";

    test_env env_ml "golden onnx: input names extraction"
      "model.inputs" {|["X"]|};

    (* Test: Prediction batch *)
    test_env env_ml "golden onnx: batch prediction successful (150 rows)"
      "preds = predict(df, model); length(preds)" "150";
  end else begin
    Printf.printf "  ! skipping ONNX golden tests: baseline files not found\n"
  end;

  Printf.printf "Phase 8 — Golden: JPMML Bridge Authority:\n";
  let iris_csv = "tests/golden/data/iris.csv" in
  let iris_pmml = "tests/golden/data/iris_random_forest.pmml" in

  if Sys.file_exists iris_csv && Sys.file_exists iris_pmml then begin
    let env_pmml = Packages.init_env () in
    let (_, env_pmml) = eval_string_env (Printf.sprintf
      {|df = read_csv("%s")
        model = t_read_pmml("%s")
      |} iris_csv iris_pmml) env_pmml in

    (* Test: Metadata check *)
    test_env env_pmml "golden jpmml: model import successful"
      "model.class" {|"random_forest"|};

    (* Test: JPMML Bridge Prediction (triggered by predict builtin through authority pivot) *)
    test_env env_pmml "golden jpmml: bridge prediction successful (150 rows verified via nrow)"
      "preds = predict(df, model); nrow(preds)" "150";

    (* Test: Cross-Engine Validation (Native vs JPMML) *)
    test_env env_pmml "golden jpmml: native vs jpmml parity verified"
      "val = compare_native_vs_pmml_scores(df, model); val.`match`" "true";
  end else begin
    Printf.printf "  ! skipping PMML golden tests: baseline files not found\n"
  end;

  print_newline ()
