let run_tests pass_count fail_count _eval_string eval_string_env test =
  (* === Grouped Operations Edge Cases === *)

  (* Create test CSV for edge case tests *)
  let csv_edge = "test_edge_cases.csv" in
  let oc = open_out csv_edge in
  output_string oc "name,category,value\nAlice,A,10\nBob,B,20\nCharlie,A,30\nDiana,B,40\nEve,A,50\n";
  close_out oc;

  let env0 = Eval.initial_env () in
  let (_, env0) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_edge) env0 in

  Printf.printf "Edge Cases — Empty Groups (filter to zero rows):\n";

  (* Filter to nonexistent category then group_by *)
  let (v, _) = eval_string_env
    {|df |> filter($category == "nonexistent") |> group_by($category) |> summarize($count = nrow($category))|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  if String.length result >= 9 && String.sub result 0 9 = "DataFrame" then begin
    incr pass_count; Printf.printf "  ✓ filter to empty then group_by+summarize returns DataFrame\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ filter to empty then group_by+summarize returns DataFrame\n    Got: %s\n" result
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

  let env_na = Eval.initial_env () in
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
    let result = Ast.Utils.value_to_string v in
    if String.length result >= 9 && String.sub result 0 9 = "DataFrame" then begin
      incr pass_count; Printf.printf "  ✓ grouped summarize with all-NA values returns DataFrame\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ grouped summarize with all-NA values returns DataFrame\n    Got: %s\n" result
    end
  | Error msg ->
    incr fail_count; Printf.printf "  ✗ grouped summarize with all-NA values\n    EXCEPTION: %s\n" msg);

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

  let env_single = Eval.initial_env () in
  let (_, env_single) = eval_string_env (Printf.sprintf {|df_single = read_csv("%s")|} csv_single) env_single in

  (* group_by unique id, then summarize with sd — each group has 1 row *)
  let (v, _) = eval_string_env
    {|df_single |> group_by($id) |> summarize($count = nrow($id))|}
    env_single in
  let result = Ast.Utils.value_to_string v in
  if String.length result >= 9 && String.sub result 0 9 = "DataFrame" then begin
    incr pass_count; Printf.printf "  ✓ single-row groups summarize produces DataFrame\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ single-row groups summarize produces DataFrame\n    Got: %s\n" result
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

  let env_multi = Eval.initial_env () in
  let (_, env_multi) = eval_string_env (Printf.sprintf {|df_multi = read_csv("%s")|} csv_multi) env_multi in

  (* group_by two columns *)
  let (v, _) = eval_string_env
    {|df_multi |> group_by($dept, $role) |> summarize($count = nrow($dept))|}
    env_multi in
  let result = Ast.Utils.value_to_string v in
  if String.length result >= 9 && String.sub result 0 9 = "DataFrame" then begin
    incr pass_count; Printf.printf "  ✓ group_by two columns produces DataFrame\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ group_by two columns produces DataFrame\n    Got: %s\n" result
  end;

  (try Sys.remove csv_multi with _ -> ());
  print_newline ();

  Printf.printf "Edge Cases — Grouped Mutate Edge Cases:\n";

  (* Grouped mutate on single-row groups *)
  let csv_gm = "test_grouped_mutate_edge.csv" in
  let oc_gm = open_out csv_gm in
  output_string oc_gm "id,value\n1,10\n2,20\n3,30\n";
  close_out oc_gm;

  let env_gm = Eval.initial_env () in
  let (_, env_gm) = eval_string_env (Printf.sprintf {|df_gm = read_csv("%s")|} csv_gm) env_gm in

  let (v, _) = eval_string_env
    {|df_gm |> group_by($id) |> mutate($grp_size = nrow($id))|}
    env_gm in
  let result = Ast.Utils.value_to_string v in
  if String.length result >= 9 && String.sub result 0 9 = "DataFrame" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate on single-row groups works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate on single-row groups works\n    Got: %s\n" result
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
    {|df |> group_by($category) |> summarize($count = nrow($category), $total = sum($value))|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  if String.length result >= 9 && String.sub result 0 9 = "DataFrame" then begin
    incr pass_count; Printf.printf "  ✓ summarize with multiple aggregation pairs\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ summarize with multiple aggregation pairs\n    Got: %s\n" result
  end;

  (* Ungrouped summarize on empty DataFrame *)
  let (v, _) = eval_string_env
    {|df |> filter($category == "nonexistent") |> summarize($count = nrow($category))|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  if String.length result >= 9 && String.sub result 0 9 = "DataFrame" then begin
    incr pass_count; Printf.printf "  ✓ ungrouped summarize on filtered-empty DataFrame\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ ungrouped summarize on filtered-empty DataFrame\n    Got: %s\n" result
  end;

  print_newline ();

  (* Clean up *)
  (try Sys.remove csv_edge with _ -> ())
