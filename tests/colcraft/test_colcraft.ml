let run_tests pass_count fail_count _eval_string eval_string_env test =
  (* Create test CSV for Phase 4 tests *)
  let csv_p4 = "test_phase4.csv" in
  let oc6 = open_out csv_p4 in
  output_string oc6 "name,age,score,dept\nAlice,30,95.5,eng\nBob,25,87.3,sales\nCharlie,35,92.1,eng\nDiana,28,88.0,sales\nEve,32,91.5,eng\n";
  close_out oc6;

  let env_p4 = Eval.initial_env () in
  let (_, env_p4) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_p4) env_p4 in

  Printf.printf "Phase 4 — select():\n";
  let (v, _) = eval_string_env {|select(df, "name", "age")|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 2 cols: [name, age])" then begin
    incr pass_count; Printf.printf "  ✓ select two columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ select two columns\n    Expected: DataFrame(5 rows x 2 cols: [name, age])\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|select(df, "name")|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 1 cols: [name])" then begin
    incr pass_count; Printf.printf "  ✓ select single column\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ select single column\n    Expected: DataFrame(5 rows x 1 cols: [name])\n    Got: %s\n" result
  end;

  test "select missing column"
    (Printf.sprintf {|df = read_csv("%s"); select(df, "nonexistent")|} csv_p4)
    {|Error(KeyError: "Column(s) not found: nonexistent")|};
  test "select non-string arg"
    (Printf.sprintf {|df = read_csv("%s"); select(df, 42)|} csv_p4)
    {|Error(TypeError: "select() expects string column names")|};
  test "select non-dataframe"
    {|select(42, "name")|}
    {|Error(TypeError: "select() expects a DataFrame as first argument")|};
  test "select with pipe"
    (Printf.sprintf {|df = read_csv("%s"); df |> select("name", "score") |> ncol|} csv_p4)
    "2";
  print_newline ();

  Printf.printf "Phase 4 — filter():\n";
  let (v, _) = eval_string_env {|filter(df, \(row) row.age > 28)|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(3 rows x 4 cols: [name, age, score, dept])" then begin
    incr pass_count; Printf.printf "  ✓ filter by age > 28\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ filter by age > 28\n    Expected: DataFrame(3 rows x 4 cols: [name, age, score, dept])\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|df |> filter(\(row) row.dept == "eng") |> nrow|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ filter by dept == eng via pipe\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ filter by dept == eng via pipe\n    Expected: 3\n    Got: %s\n" result
  end;

  test "filter non-dataframe"
    {|filter(42, \(x) true)|}
    {|Error(TypeError: "filter() expects a DataFrame as first argument")|};
  print_newline ();

  Printf.printf "Phase 4 — mutate():\n";
  let (v, _) = eval_string_env {|mutate(df, "age_plus_10", \(row) row.age + 10)|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 5 cols: [name, age, score, dept, age_plus_10])" then begin
    incr pass_count; Printf.printf "  ✓ mutate adds new column\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ mutate adds new column\n    Expected: DataFrame(5 rows x 5 cols: [name, age, score, dept, age_plus_10])\n    Got: %s\n" result
  end;

  (* mutate replaces existing column *)
  let (v, _) = eval_string_env {|mutate(df, "age", \(row) row.age + 1) |> ncol|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "4" then begin
    incr pass_count; Printf.printf "  ✓ mutate replaces existing column (same col count)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ mutate replaces existing column (same col count)\n    Expected: 4\n    Got: %s\n" result
  end;

  test "mutate non-dataframe"
    {|mutate(42, "x", \(r) r)|}
    {|Error(TypeError: "mutate() expects a DataFrame as first argument")|};
  test "mutate non-string col name"
    (Printf.sprintf {|df = read_csv("%s"); mutate(df, 42, \(r) r)|} csv_p4)
    {|Error(TypeError: "mutate() expects a string column name as second argument")|};
  print_newline ();

  Printf.printf "Phase 4 — arrange():\n";
  (* Sort by age ascending — check first row name *)
  let (v, _) = eval_string_env {|df2 = arrange(df, "age"); select(df2, "name") |> \(d) d.name|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = {|Vector["Bob", "Diana", "Alice", "Eve", "Charlie"]|} then begin
    incr pass_count; Printf.printf "  ✓ arrange ascending by age\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ arrange ascending by age\n    Expected: Vector[\"Bob\", \"Diana\", \"Alice\", \"Eve\", \"Charlie\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|df2 = arrange(df, "age", "desc"); select(df2, "name") |> \(d) d.name|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = {|Vector["Charlie", "Eve", "Alice", "Diana", "Bob"]|} then begin
    incr pass_count; Printf.printf "  ✓ arrange descending by age\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ arrange descending by age\n    Expected: Vector[\"Charlie\", \"Eve\", \"Alice\", \"Diana\", \"Bob\"]\n    Got: %s\n" result
  end;

  test "arrange missing column"
    (Printf.sprintf {|df = read_csv("%s"); arrange(df, "nonexistent")|} csv_p4)
    {|Error(KeyError: "Column 'nonexistent' not found in DataFrame")|};
  test "arrange invalid direction"
    (Printf.sprintf {|df = read_csv("%s"); arrange(df, "age", "up")|} csv_p4)
    {|Error(ValueError: "arrange() direction must be "asc" or "desc", got "up"")|};

  print_newline ();

  Printf.printf "Phase 4 — group_by():\n";
  let (v, _) = eval_string_env {|group_by(df, "dept")|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 4 cols: [name, age, score, dept]) grouped by [dept]" then begin
    incr pass_count; Printf.printf "  ✓ group_by marks grouping\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ group_by marks grouping\n    Expected: DataFrame(5 rows x 4 cols: [name, age, score, dept]) grouped by [dept]\n    Got: %s\n" result
  end;

  test "group_by missing column"
    (Printf.sprintf {|df = read_csv("%s"); group_by(df, "nonexistent")|} csv_p4)
    {|Error(KeyError: "Column(s) not found: nonexistent")|};
  test "group_by non-string"
    (Printf.sprintf {|df = read_csv("%s"); group_by(df, 42)|} csv_p4)
    {|Error(TypeError: "group_by() expects string column names")|};
  test "group_by no columns"
    (Printf.sprintf {|df = read_csv("%s"); group_by(df)|} csv_p4)
    {|Error(ArityError: "group_by() requires at least one column name")|};
  print_newline ();

  Printf.printf "Phase 4 — summarize():\n";
  (* Ungrouped summarize *)
  let (v, _) = eval_string_env {|summarize(df, "total_rows", \(d) nrow(d))|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(1 rows x 1 cols: [total_rows])" then begin
    incr pass_count; Printf.printf "  ✓ ungrouped summarize produces 1-row result\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ ungrouped summarize produces 1-row result\n    Expected: DataFrame(1 rows x 1 cols: [total_rows])\n    Got: %s\n" result
  end;

  (* Grouped summarize *)
  let (v, _) = eval_string_env
    {|df |> group_by("dept") |> summarize("count", \(g) nrow(g))|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(2 rows x 2 cols: [dept, count])" then begin
    incr pass_count; Printf.printf "  ✓ grouped summarize produces per-group result\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped summarize produces per-group result\n    Expected: DataFrame(2 rows x 2 cols: [dept, count])\n    Got: %s\n" result
  end;

  (* Check grouped summarize values *)
  let (v, _) = eval_string_env
    {|result = df |> group_by("dept") |> summarize("count", \(g) nrow(g)); result.count|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[3, 2]" then begin
    incr pass_count; Printf.printf "  ✓ grouped summarize correct counts (eng=3, sales=2)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped summarize correct counts (eng=3, sales=2)\n    Expected: Vector[3, 2]\n    Got: %s\n" result
  end;

  test "summarize non-dataframe"
    {|summarize(42, "x", \(d) d)|}
    {|Error(TypeError: "summarize() expects a DataFrame as first argument")|};
  print_newline ();

  Printf.printf "Phase 4 — Pipeline Integration:\n";
  test "tidy-style pipeline"
    (Printf.sprintf
      {|df = read_csv("%s")
df |> filter(\(row) row.age > 25)
  |> select("name", "score")
  |> arrange("score", "desc")
  |> nrow|} csv_p4)
    "4";
  test "mutate + filter pipeline"
    (Printf.sprintf
      {|df = read_csv("%s")
df |> mutate("senior", \(row) row.age >= 30)
  |> filter(\(row) row.senior == true)
  |> nrow|} csv_p4)
    "3";
  print_newline ();

  Printf.printf "Phase 4 — Grouped Mutate:\n";
  (* Grouped mutate: broadcast group size to each row *)
  let (v, _) = eval_string_env
    {|df |> group_by("dept") |> mutate("dept_size", \(g) nrow(g))|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 5 cols: [name, age, score, dept, dept_size]) grouped by [dept]" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate adds column with group context\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate adds column with group context\n    Expected: DataFrame(5 rows x 5 cols: [name, age, score, dept, dept_size]) grouped by [dept]\n    Got: %s\n" result
  end;

  (* Grouped mutate: check broadcast values *)
  let (v, _) = eval_string_env
    {|result = df |> group_by("dept") |> mutate("dept_size", \(g) nrow(g)); result.dept_size|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  (* eng has 3 rows (Alice, Charlie, Eve), sales has 2 rows (Bob, Diana) *)
  (* Original order: Alice(eng=3), Bob(sales=2), Charlie(eng=3), Diana(sales=2), Eve(eng=3) *)
  if result = "Vector[3, 2, 3, 2, 3]" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate broadcasts group values correctly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate broadcasts group values correctly\n    Expected: Vector[3, 2, 3, 2, 3]\n    Got: %s\n" result
  end;

  (* Grouped mutate: preserves group keys *)
  let (v, _) = eval_string_env
    {|df |> group_by("dept") |> mutate("x", \(g) 1)|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 5 cols: [name, age, score, dept, x]) grouped by [dept]" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate preserves group keys\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate preserves group keys\n    Expected: DataFrame(5 rows x 5 cols: [name, age, score, dept, x]) grouped by [dept]\n    Got: %s\n" result
  end;

  (* Grouped mutate: compute group mean score *)
  let (v, _) = eval_string_env
    {|result = df |> group_by("dept") |> mutate("mean_score", \(g) mean(g.score)); result.mean_score|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  (* eng scores: 95.5, 92.1, 91.5 -> mean = 93.0333333333 *)
  (* sales scores: 87.3, 88.0 -> mean = 87.65 *)
  (* Original order: Alice(eng), Bob(sales), Charlie(eng), Diana(sales), Eve(eng) *)
  let contains s sub =
    let slen = String.length s in
    let sublen = String.length sub in
    let rec check i = if i > slen - sublen then false
      else if String.sub s i sublen = sub then true else check (i + 1)
    in check 0
  in
  if contains result "93.03333" && contains result "87.65" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate computes group mean\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate computes group mean\n    Expected eng mean ~93.03 and sales mean ~87.65\n    Got: %s\n" result
  end;

  (* Grouped mutate followed by ungrouped operation *)
  let (v, _) = eval_string_env
    {|df |> group_by("dept") |> mutate("dept_size", \(g) nrow(g)) |> filter(\(row) row.dept_size > 2) |> nrow|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate chains with filter\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate chains with filter\n    Expected: 3\n    Got: %s\n" result
  end;

  (* Ungrouped mutate still works (regression check) *)
  let (v, _) = eval_string_env {|mutate(df, "age_x2", \(row) row.age * 2) |> ncol|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "5" then begin
    incr pass_count; Printf.printf "  ✓ ungrouped mutate still works (regression)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ ungrouped mutate still works (regression)\n    Expected: 5\n    Got: %s\n" result
  end;

  print_newline ();

  (* Clean up Phase 4 CSV *)
  (try Sys.remove csv_p4 with _ -> ())
