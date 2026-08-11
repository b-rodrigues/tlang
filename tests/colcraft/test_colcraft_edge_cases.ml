
let run_tests pass_count fail_count _failures _eval_string eval_string_env test test_env =
  (* === Grouped Operations Edge Cases === *)

  (* Create test CSV for edge case tests *)
  let csv_edge = "test_edge_cases.csv" in
  let oc = open_out csv_edge in
  output_string oc "name,category,value\nAlice,A,10\nBob,B,20\nCharlie,A,30\nDiana,B,40\nEve,A,50\n";
  close_out oc;

  let env0 = Packages.init_env () in
  let env0 = Test_helpers.eval_setup eval_string_env env0 "test_colcraft_edge_cases:12" (Printf.sprintf {|df = read_csv("%s")|} csv_edge) in

  Printf.printf "Edge Cases — Empty Groups (filter to zero rows):\n";

  (* Filter to nonexistent category then group_by *)
  test_env env0 "filter to empty then group_by+summarize returns 0 rows"
    {|df |> filter($category == "nonexistent") |> group_by($category) |> summarize($count = nrow($category)) |> nrow|}
    "0";

  (* Filter to zero rows produces 0-row DataFrame *)
  test_env env0 "filter to zero rows gives nrow=0"
    {|df |> filter($category == "nonexistent") |> nrow|}
    "0";

  print_newline ();

  Printf.printf "Edge Cases — All-NA Groups:\n";

  let csv_na = "test_na_groups.csv" in
  let oc_na = open_out csv_na in
  output_string oc_na "name,value\nA,\nB,\nA,\n";
  close_out oc_na;

  let env_na = Packages.init_env () in
  let env_na = Test_helpers.eval_setup eval_string_env env_na "test_colcraft_edge_cases:36" (Printf.sprintf {|df_na = read_csv("%s")|} csv_na) in

  (* Grouped summarize with mean(na_rm=true) on all-NA values *)
  let step_result = (try
    let (v, _) = eval_string_env
      {|df_na |> group_by($name) |> summarize($mean_val = mean($value, na_rm = true))|}
      env_na in
    Ok v
  with e -> Error (Printexc.to_string e))
  in
  (match step_result with
  | Ok v ->
    let (v_nrow, _) = eval_string_env {|nrow(ans)|} (Ast.Env.add "ans" v env_na) in
    let result_nrow = Ast.Utils.value_to_string v_nrow in
    if result_nrow = "2" then begin
      incr pass_count; Printf.printf "  ✓ grouped summarize with all-NA values returns 2 rows\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ grouped summarize with all-NA values: expected 2 rows, got %s\n" result_nrow
    end
  | Error msg ->
    incr fail_count; Printf.printf "  ✗ grouped summarize with all-NA values\n    EXCEPTION: %s\n" msg);

  test_env env_na "repeated grouped aggs on nullable column preserve NA error semantics"
    {|df_na |> group_by($name) |> summarize($min_val = min($value), $max_val = max($value))|}
    {|Error(AggregationError: "Function `min` encountered NA value. Handle missingness explicitly or set `na_rm` to true.")|};

  (* mean on all-NA with na_rm=true returns NA *)
  test "mean all-NA na_rm=true returns NA(Float)"
    "mean([NA, NA, NA], na_rm = true)"
    "NA(Float)";

  (try Sys.remove csv_na with _ -> ());
  print_newline ();

  Printf.printf "Edge Cases — Single-Row Groups:\n";

  let csv_single = "test_single_groups.csv" in
  let oc_single = open_out csv_single in
  output_string oc_single "id,value\n1,10\n2,20\n3,30\n";
  close_out oc_single;

  let env_single = Packages.init_env () in
  let env_single = Test_helpers.eval_setup eval_string_env env_single "test_colcraft_edge_cases:78" (Printf.sprintf {|df_single = read_csv("%s")|} csv_single) in

  (* group_by unique id, then summarize with sd — each group has 1 row *)
  test_env env_single "single-row groups summarize produces 3 rows"
    {|df_single |> group_by($id) |> summarize($count = nrow($id)) |> nrow|}
    "3";

  (* Check single-row group count values *)
  test_env env_single "single-row groups each have count=1"
    {|result = df_single |> group_by($id) |> summarize($count = nrow($id)); result.count|}
    "Vector[1, 1, 1]";

  (* sd of single value should return Error *)
  test "sd of single value"
    "sd([42])"
    {|Error(ValueError: "Function `sd` requires at least 2 values.")|};

  (try Sys.remove csv_single with _ -> ());
  print_newline ();

  Printf.printf "Edge Cases — Multiple Group Keys:\n";

  let csv_multi = "test_multi_groups.csv" in
  let oc_multi = open_out csv_multi in
  output_string oc_multi "dept,role,salary\neng,senior,100\neng,junior,60\nsales,senior,90\nsales,junior,55\neng,senior,110\n";
  close_out oc_multi;

  let env_multi = Packages.init_env () in
  let env_multi = Test_helpers.eval_setup eval_string_env env_multi "test_colcraft_edge_cases:106" (Printf.sprintf {|df_multi = read_csv("%s")|} csv_multi) in

  (* group_by two columns *)
  test_env env_multi "group_by two columns produces 4 rows"
    {|df_multi |> group_by($dept, $role) |> summarize($count = nrow($dept)) |> nrow|}
    "4";

  (try Sys.remove csv_multi with _ -> ());
  print_newline ();

  Printf.printf "Edge Cases — Grouped Mutate Edge Cases:\n";

  (* Grouped mutate on single-row groups *)
  let csv_gm = "test_grouped_mutate_edge.csv" in
  let oc_gm = open_out csv_gm in
  output_string oc_gm "id,value\n1,10\n2,20\n3,30\n";
  close_out oc_gm;

  let env_gm = Packages.init_env () in
  let env_gm = Test_helpers.eval_setup eval_string_env env_gm "test_colcraft_edge_cases:125" (Printf.sprintf {|df_gm = read_csv("%s")|} csv_gm) in

  test_env env_gm "grouped mutate on single-row groups returns 3 rows"
    {|df_gm |> group_by($id) |> mutate($grp_size = nrow($id)) |> nrow|}
    "3";

  (* Check grouped mutate broadcasts correct values *)
  test_env env_gm "grouped mutate broadcasts 1 for single-row groups"
    {|result = df_gm |> group_by($id) |> mutate($grp_size = nrow($id)); result.grp_size|}
    "Vector[1, 1, 1]";

  (try Sys.remove csv_gm with _ -> ());
  print_newline ();

  Printf.printf "Edge Cases — Summarize with Multiple Aggregation Functions:\n";

  (* Multiple aggregation pairs in a single summarize *)
  test_env env0 "summarize with multiple aggregation pairs returns 2 rows"
    {|df |> group_by($category) |> summarize($count = nrow($category), $total = sum($value)) |> nrow|}
    "2";

  (* Ungrouped summarize on empty DataFrame *)
  test_env env0 "ungrouped summarize on filtered-empty DataFrame returns 1 row"
    {|df |> filter($category == "nonexistent") |> summarize($count = nrow($category)) |> nrow|}
    "1";

  print_newline ();

  Printf.printf "Edge Cases — Mutate Constant/Scalar Column Assignment:\n";

  (* mutate with numeric constant *)
  test_env env0 "mutate constant float replicates across all rows"
    {|result = mutate(df, $const_num = 1.0); result.const_num|}
    "Vector[1., 1., 1., 1., 1.]";

  (* mutate with string constant *)
  test_env env0 "mutate constant string replicates across all rows"
    {|result = mutate(df, $const_str = "x"); result.const_str|}
    {|Vector["x", "x", "x", "x", "x"]|};

  (* mutate with integer constant *)
  test_env env0 "mutate constant integer replicates across all rows"
    {|result = mutate(df, $const_int = 42); result.const_int|}
    "Vector[42, 42, 42, 42, 42]";

  (* grouped mutate with constant — constant must replicate within each group *)
  test_env env0 "grouped mutate constant string replicates across all rows"
    {|result = df |> group_by($category) |> mutate($label = "fixed"); result.label|}
    {|Vector["fixed", "fixed", "fixed", "fixed", "fixed"]|};

  print_newline ();

  Printf.printf "Edge Cases — Nested Verb Calls (NSE transform):\n";

  (* Nested select() inside mutate() must evaluate to a DataFrame, not be
     wrapped into a row-lambda by the NSE argument transform. *)
  test_env env0 "nested select call as mutate first arg yields expected columns"
    {|res = mutate(select(df, $value), $z = $value * 2); [ncol(res), nrow(res), res.z]|}
    {|[2, 5, Vector[20, 40, 60, 80, 100]]|};

  (* Nested arrange() inside arrange() must stay raw (idempotence via nesting). *)
  test_env env0 "nested arrange call as arrange first arg stays raw"
    {|identical(arrange(arrange(df, $value), $value), arrange(df, $value))|}
    "true";

  (* Named assign-from-DataFrame via nested select() must extract the column. *)
  test_env env0 "nested select call as mutate named value assigns column"
    {|res = mutate(df, $y = select(df, $value)); res.y|}
    "Vector[10., 20., 30., 40., 50.]";

  (* Bare string select() nested in mutate still works. *)
  test_env env0 "nested string-select call as mutate first arg"
    {|ncol(mutate(select(df, "value"), $z = 1))|}
    "2";

  print_newline ();

  (* Clean up *)
  (try Sys.remove csv_edge with _ -> ())
