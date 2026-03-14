open Str

let run_tests pass_count fail_count _eval_string eval_string_env test =
  let strip_location s =
    let re = Str.regexp "\\[[^]]*L[0-9]+:C[0-9]+\\] " in
    Str.global_replace re "" s
  in
  (* === Grouped Operations Edge Cases === *)

  (* Create test CSV for edge case tests *)
  let csv_edge = "test_edge_cases.csv" in
  let oc = open_out csv_edge in
  output_string oc "name,category,value\nAlice,A,10\nBob,B,20\nCharlie,A,30\nDiana,B,40\nEve,A,50\n";
  close_out oc;

  let env0 = Packages.init_env () in
  let (_, env0) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_edge) env0 in

  Printf.printf "Edge Cases — Empty Groups (filter to zero rows):\n";

  (* Filter to nonexistent category then group_by *)
  let (v2, _) = eval_string_env
    {|df |> filter($category == "nonexistent") |> group_by($category) |> summarize($count = nrow($category)) |> nrow|}
    env0 in
  let result2 = Ast.Utils.value_to_string v2 in
  if result2 = "0" then begin
    incr pass_count; Printf.printf "  ✓ filter to empty then group_by+summarize returns 0 rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ filter to empty then group_by+summarize should return 0 rows\n    Got: %s\n" result2
  end;

  (* Filter to zero rows produces 0-row DataFrame *)
  let (v, _) = eval_string_env
    {|df |> filter($category == "nonexistent") |> nrow|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  if result = "0" then begin
    incr pass_count; Printf.printf "  ✓ filter to zero rows gives nrow=0\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ filter to zero rows gives nrow=0\n    Expected: 0\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Edge Cases — All-NA Groups:\n";

  let csv_na = "test_na_groups.csv" in
  let oc_na = open_out csv_na in
  output_string oc_na "name,value\nA,\nB,\nA,\n";
  close_out oc_na;

  let env_na = Packages.init_env () in
  let (_, env_na) = eval_string_env (Printf.sprintf {|df_na = read_csv("%s")|} csv_na) env_na in

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

  let (v_repeat_agg, _) = eval_string_env
    {|df_na |> group_by($name) |> summarize($min_val = min($value), $max_val = max($value))|}
    env_na in
  let result_repeat_agg = strip_location (Ast.Utils.value_to_string v_repeat_agg) in
  if result_repeat_agg = {|Error(TypeError: "Function `min` encountered NA value. Handle missingness explicitly.")|} then begin
    incr pass_count; Printf.printf "  ✓ repeated grouped aggs on nullable column preserve NA error semantics\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ repeated grouped aggs on nullable column preserve NA error semantics\n    Expected min() NA error, got %s\n" result_repeat_agg
  end;

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
  let (_, env_single) = eval_string_env (Printf.sprintf {|df_single = read_csv("%s")|} csv_single) env_single in

  (* group_by unique id, then summarize with sd — each group has 1 row *)
  let (v, _) = eval_string_env
    {|df_single |> group_by($id) |> summarize($count = nrow($id)) |> nrow|}
    env_single in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ single-row groups summarize produces 3 rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ single-row groups summarize produces 3 rows\n    Expected: 3, Got: %s\n" result
  end;

  (* Check single-row group count values *)
  let (v, _) = eval_string_env
    {|result = df_single |> group_by($id) |> summarize($count = nrow($id)); result.count|}
    env_single in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 1, 1]" then begin
    incr pass_count; Printf.printf "  ✓ single-row groups each have count=1\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ single-row groups each have count=1\n    Expected: Vector[1, 1, 1]\n    Got: %s\n" result
  end;

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
  let (_, env_multi) = eval_string_env (Printf.sprintf {|df_multi = read_csv("%s")|} csv_multi) env_multi in

  (* group_by two columns *)
  let (v, _) = eval_string_env
    {|df_multi |> group_by($dept, $role) |> summarize($count = nrow($dept)) |> nrow|}
    env_multi in
  let result = Ast.Utils.value_to_string v in
  if result = "4" then begin
    incr pass_count; Printf.printf "  ✓ group_by two columns produces 4 rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ group_by two columns produces 4 rows\n    Expected: 4, Got: %s\n" result
  end;

  (try Sys.remove csv_multi with _ -> ());
  print_newline ();

  Printf.printf "Edge Cases — Grouped Mutate Edge Cases:\n";

  (* Grouped mutate on single-row groups *)
  let csv_gm = "test_grouped_mutate_edge.csv" in
  let oc_gm = open_out csv_gm in
  output_string oc_gm "id,value\n1,10\n2,20\n3,30\n";
  close_out oc_gm;

  let env_gm = Packages.init_env () in
  let (_, env_gm) = eval_string_env (Printf.sprintf {|df_gm = read_csv("%s")|} csv_gm) env_gm in

  let (v, _) = eval_string_env
    {|df_gm |> group_by($id) |> mutate($grp_size = nrow($id)) |> nrow|}
    env_gm in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate on single-row groups returns 3 rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate on single-row groups returns 3 rows\n    Expected: 3, Got: %s\n" result
  end;

  (* Check grouped mutate broadcasts correct values *)
  let (v, _) = eval_string_env
    {|result = df_gm |> group_by($id) |> mutate($grp_size = nrow($id)); result.grp_size|}
    env_gm in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 1, 1]" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate broadcasts 1 for single-row groups\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate broadcasts 1 for single-row groups\n    Expected: Vector[1, 1, 1]\n    Got: %s\n" result
  end;

  (try Sys.remove csv_gm with _ -> ());
  print_newline ();

  Printf.printf "Edge Cases — Summarize with Multiple Aggregation Functions:\n";

  (* Multiple aggregation pairs in a single summarize *)
  let (v, _) = eval_string_env
    {|df |> group_by($category) |> summarize($count = nrow($category), $total = sum($value)) |> nrow|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ summarize with multiple aggregation pairs returns 2 rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ summarize with multiple aggregation pairs returns 2 rows\n    Expected: 2, Got: %s\n" result
  end;

  (* Ungrouped summarize on empty DataFrame *)
  let (v, _) = eval_string_env
    {|df |> filter($category == "nonexistent") |> summarize($count = nrow($category)) |> nrow|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  if result = "1" then begin
    incr pass_count; Printf.printf "  ✓ ungrouped summarize on filtered-empty DataFrame returns 1 row\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ ungrouped summarize on filtered-empty DataFrame returns 1 row\n    Expected: 1, Got: %s\n" result
  end;

  print_newline ();

  (* Clean up *)
  (try Sys.remove csv_edge with _ -> ())
