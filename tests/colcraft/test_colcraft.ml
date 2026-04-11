let capture_stderr f =
  let stderr_fd = Unix.descr_of_out_channel stderr in
  let saved_stderr = Unix.dup stderr_fd in
  let read_fd, write_fd = Unix.pipe () in
  Unix.dup2 write_fd stderr_fd;
  Unix.close write_fd;
  let restore () =
    flush stderr;
    Unix.dup2 saved_stderr stderr_fd;
    Unix.close saved_stderr
  in
  try
    let result = f () in
    restore ();
    let buffer = Buffer.create 128 in
    let chunk = Bytes.create 256 in
    let rec drain () =
      match Unix.read read_fd chunk 0 (Bytes.length chunk) with
      | 0 -> ()
      | n ->
          Buffer.add_subbytes buffer chunk 0 n;
          drain ()
    in
    drain ();
    Unix.close read_fd;
    (result, Buffer.contents buffer)
  with exn ->
    restore ();
    Unix.close read_fd;
    raise exn

let run_tests pass_count fail_count _eval_string eval_string_env test =
  (* Create test CSV for Phase 4 tests *)
  let csv_p4 = "test_phase4.csv" in
  let oc6 = open_out csv_p4 in
  output_string oc6 "name,age,score,dept\nAlice,30,95.5,eng\nBob,25,87.3,sales\nCharlie,35,92.1,eng\nDiana,28,88.0,sales\nEve,32,91.5,eng\n";
  close_out oc6;

  let env_p4 = Packages.init_env () in
  let (_, env_p4) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_p4) env_p4 in

  Printf.printf "Phase 4 — select():\n";
  let (v, _) = eval_string_env {|select(df, $name, $age)|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 2 cols: [name, age])" then begin
    incr pass_count; Printf.printf "  ✓ select two columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ select two columns\n    Expected: DataFrame(5 rows x 2 cols: [name, age])\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|select(df, $name)|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 1 cols: [name])" then begin
    incr pass_count; Printf.printf "  ✓ select single column\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ select single column\n    Expected: DataFrame(5 rows x 1 cols: [name])\n    Got: %s\n" result
  end;

  test "select missing column"
    (Printf.sprintf {|df = read_csv("%s"); select(df, $nonexistent)|} csv_p4)
    {|Error(KeyError: "Column(s) not found: nonexistent.")|};
  test "select non-column arg"
    (Printf.sprintf {|df = read_csv("%s"); select(df, 42)|} csv_p4)
    {|Error(TypeError: "Function `select` expects $column syntax.")|};
  test "select non-dataframe"
    {|select(42, $name)|}
    {|Error(TypeError: "Function `select` expects a DataFrame as first argument.")|};
  test "select with pipe"
    (Printf.sprintf {|df = read_csv("%s"); df |> select($name, $score) |> ncol|} csv_p4)
    "2";
  print_newline ();

  Printf.printf "Phase 4 — filter():\n";
  let (v, _) = eval_string_env {|filter(df, $age > 28)|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(3 rows x 4 cols: [name, age, score, dept])" then begin
    incr pass_count; Printf.printf "  ✓ filter by $age > 28\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ filter by $age > 28\n    Expected: DataFrame(3 rows x 4 cols: [name, age, score, dept])\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|df |> filter($dept == "eng") |> nrow|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ filter by $dept == eng via pipe\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ filter by $dept == eng via pipe\n    Expected: 3\n    Got: %s\n" result
  end;

  test "filter non-dataframe"
    {|filter(42, \(x) true)|}
    {|Error(TypeError: "Function `filter` expects a DataFrame as first argument.")|};
  test "filter excludes rows where predicate sees NA"
    {|df_na_filter = dataframe([[x: 1], [x: NA], [x: 3]]); filter(df_na_filter, $x > 1) |> nrow|}
    "1";
  let show_warnings_before = !Eval.show_warnings in
  let ((v_warn, _), warning_text) =
    Fun.protect
      (fun () ->
        Eval.show_warnings := true;
        capture_stderr (fun () ->
          eval_string_env
            {|df_na_warn = dataframe([[x: 1], [x: NA], [x: 3]]); filter(df_na_warn, $x > 1) |> nrow|}
            env_p4))
      ~finally:(fun () -> Eval.show_warnings := show_warnings_before)
  in
  let result_warn = Ast.Utils.value_to_string v_warn in
  let has_warning =
    try
      let _ =
        Str.search_forward
          (Str.regexp "Warning: filter() excluded 1 row because the predicate evaluated to NA")
          warning_text 0
      in
      true
    with Not_found -> false
  in
  if result_warn = "1" && has_warning then begin
    incr pass_count; Printf.printf "  ✓ filter vectorized path warns when NA rows are excluded\n"
  end else begin
    incr fail_count;
    Printf.printf
      "  ✗ filter vectorized path warns when NA rows are excluded\n    Expected nrow=1 with warning\n    Got result: %s\n    Warning: %s\n"
      result_warn warning_text
  end;
  print_newline ();

  Printf.printf "Phase 4 — mutate():\n";
  let (v, _) = eval_string_env {|mutate(df, $age_plus_10 = $age + 10)|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 5 cols: [name, age, score, dept, age_plus_10])" then begin
    incr pass_count; Printf.printf "  ✓ mutate adds new column\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ mutate adds new column\n    Expected: DataFrame(5 rows x 5 cols: [name, age, score, dept, age_plus_10])\n    Got: %s\n" result
  end;

  (* mutate replaces existing column *)
  let (v, _) = eval_string_env {|mutate(df, $age = $age + 1) |> ncol|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "4" then begin
    incr pass_count; Printf.printf "  ✓ mutate replaces existing column (same col count)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ mutate replaces existing column (same col count)\n    Expected: 4\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env
    {|result = mutate(df, $score_per_age_pct = ($score / $age) * 100.0); result.score_per_age_pct|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = {|Vector[318.333333333, 349.2, 263.142857143, 314.285714286, 285.9375]|} then begin
    incr pass_count; Printf.printf "  ✓ mutate vectorizes nested arithmetic in one expression\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ mutate vectorizes nested arithmetic in one expression\n    Expected: Vector[318.333333333, 349.2, 263.142857143, 314.285714286, 285.9375]\n    Got: %s\n" result
  end;

  test "mutate non-dataframe"
    {|mutate(42, $x = 1)|}
    {|Error(TypeError: "Function `mutate` expects a DataFrame as first argument.")|};
  test "mutate zero args"
    {|mutate()|}
    {|Error(ArityError: "Function `mutate` expects 2 arguments but received 0.")|};
  test "mutate missing column expr"
    (Printf.sprintf {|df = read_csv("%s"); mutate(df, 42)|} csv_p4)
    {|Error(TypeError: "Function `mutate` expects $column = expr syntax.")|};
  print_newline ();

  Printf.printf "Phase 4 — arrange():\n";
  (* Sort by age ascending — check first row name *)
  let (v, _) = eval_string_env {|df2 = arrange(df, $age); select(df2, $name) |> \(d) d.name|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = {|Vector["Bob", "Diana", "Alice", "Eve", "Charlie"]|} then begin
    incr pass_count; Printf.printf "  ✓ arrange ascending by age\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ arrange ascending by age\n    Expected: Vector[\"Bob\", \"Diana\", \"Alice\", \"Eve\", \"Charlie\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|df2 = arrange(df, $age, "desc"); select(df2, $name) |> \(d) d.name|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = {|Vector["Charlie", "Eve", "Alice", "Diana", "Bob"]|} then begin
    incr pass_count; Printf.printf "  ✓ arrange descending by age\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ arrange descending by age\n    Expected: Vector[\"Charlie\", \"Eve\", \"Alice\", \"Diana\", \"Bob\"]\n    Got: %s\n" result
  end;

  test "arrange missing column"
    (Printf.sprintf {|df = read_csv("%s"); arrange(df, $nonexistent)|} csv_p4)
    {|Error(KeyError: "Column `nonexistent` not found in DataFrame.")|};
  test "arrange invalid direction"
    (Printf.sprintf {|df = read_csv("%s"); arrange(df, $age, "up")|} csv_p4)
    {|Error(ValueError: "Function `arrange` direction must be "asc" or "desc", got "up".")|};

  print_newline ();

  Printf.printf "Phase 4 — group_by():\n";
  let (v, _) = eval_string_env {|group_by(df, $dept)|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 4 cols: [name, age, score, dept]) grouped by [dept]" then begin
    incr pass_count; Printf.printf "  ✓ group_by marks grouping\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ group_by marks grouping\n    Expected: DataFrame(5 rows x 4 cols: [name, age, score, dept]) grouped by [dept]\n    Got: %s\n" result
  end;

  test "group_by missing column"
    (Printf.sprintf {|df = read_csv("%s"); group_by(df, $nonexistent)|} csv_p4)
    {|Error(KeyError: "Column(s) not found: nonexistent.")|};
  test "group_by non-column"
    (Printf.sprintf {|df = read_csv("%s"); group_by(df, 42)|} csv_p4)
    {|Error(TypeError: "Function `group_by` expects $column syntax.")|};
  test "group_by no columns"
    (Printf.sprintf {|df = read_csv("%s"); group_by(df)|} csv_p4)
    {|Error(ArityError: "Function `group_by` requires at least one $column.")|};
  print_newline ();

  Printf.printf "Phase 4 — ungroup():\n";
  let (v, _) = eval_string_env {|df |> group_by($dept) |> ungroup|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 4 cols: [name, age, score, dept])" then begin
    incr pass_count; Printf.printf "  ✓ ungroup removes grouping\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ ungroup removes grouping\n    Expected: DataFrame(5 rows x 4 cols: [name, age, score, dept])\n    Got: %s\n" result
  end;

  test "ungroup on ungrouped dataframe"
    (Printf.sprintf {|df = read_csv("%s"); ungroup(df)|} csv_p4)
    "DataFrame(5 rows x 4 cols: [name, age, score, dept])";
  test "ungroup non-dataframe"
    {|ungroup(42)|}
    {|Error(TypeError: "Function `ungroup` expects a DataFrame as first argument.")|};
  print_newline ();

  Printf.printf "Phase 4 — summarize():\n";
  (* Ungrouped summarize *)
  let (v, _) = eval_string_env {|summarize(df, $total_rows = nrow(df))|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(1 rows x 1 cols: [total_rows])" then begin
    incr pass_count; Printf.printf "  ✓ ungrouped summarize produces 1-row result\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ ungrouped summarize produces 1-row result\n    Expected: DataFrame(1 rows x 1 cols: [total_rows])\n    Got: %s\n" result
  end;

  (* Grouped summarize *)
  let (v, _) = eval_string_env
    {|df |> group_by($dept) |> summarize($count = nrow($dept))|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(2 rows x 2 cols: [dept, count])" then begin
    incr pass_count; Printf.printf "  ✓ grouped summarize produces per-group result\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped summarize produces per-group result\n    Expected: DataFrame(2 rows x 2 cols: [dept, count])\n    Got: %s\n" result
  end;

  (* Check grouped summarize values *)
  let (v, _) = eval_string_env
    {|result = df |> group_by($dept) |> summarize($count = nrow($dept)); result.count|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[3, 2]" then begin
    incr pass_count; Printf.printf "  ✓ grouped summarize correct counts (eng=3, sales=2)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped summarize correct counts (eng=3, sales=2)\n    Expected: Vector[3, 2]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env
    {|result = df |> group_by($dept) |> summarize($count = n()); result.count|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[3, 2]" then begin
    incr pass_count; Printf.printf "  ✓ grouped summarize n() counts rows per group\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped summarize n() counts rows per group\n    Expected: Vector[3, 2]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env
    {|result = summarize(df, $uniq_dept = n_distinct($dept)); to_integer(sum(result.uniq_dept))|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ summarize n_distinct() counts unique values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ summarize n_distinct() counts unique values\n    Expected: 2\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env
    {|n_distinct([to_float("NaN"), to_float("NaN"), 1.0])|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ n_distinct() treats repeated NaN values as one distinct value\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ n_distinct() repeated NaN handling\n    Expected: 2\n    Got: %s\n" result
  end;

  test "n public arity remains zero-arg"
    {|n(1, 2)|}
    {|Error(ArityError: "Function `n` expects 0 arguments but received 2.")|};

  test "summarize non-dataframe"
    {|summarize(42, $x = 1)|}
    {|Error(TypeError: "Function `summarize` expects a DataFrame as first argument.")|};
  print_newline ();

  Printf.printf "Phase 4 — Pipeline Integration:\n";
  test "tidy-style pipeline"
    (Printf.sprintf
      {|df = read_csv("%s")
df |> filter($age > 25)
  |> select($name, $score)
  |> arrange($score, "desc")
  |> nrow|} csv_p4)
    "4";
  test "mutate + filter pipeline"
    (Printf.sprintf
      {|df = read_csv("%s")
df |> mutate($senior = $age >= 30)
  |> filter($senior == true)
  |> nrow|} csv_p4)
    "3";
  print_newline ();

  Printf.printf "Phase 4 — Grouped Mutate:\n";
  (* Grouped mutate: broadcast group size to each row *)
  let (v, _) = eval_string_env
    {|df |> group_by($dept) |> mutate($dept_size = nrow($dept))|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 5 cols: [name, age, score, dept, dept_size]) grouped by [dept]" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate adds column with group context\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate adds column with group context\n    Expected: DataFrame(5 rows x 5 cols: [name, age, score, dept, dept_size]) grouped by [dept]\n    Got: %s\n" result
  end;

  (* Grouped mutate: check broadcast values *)
  let (v, _) = eval_string_env
    {|result = df |> group_by($dept) |> mutate($dept_size = nrow($dept)); result.dept_size|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[3, 2, 3, 2, 3]" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate broadcasts group values correctly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate broadcasts group values correctly\n    Expected: Vector[3, 2, 3, 2, 3]\n    Got: %s\n" result
  end;

  (* Grouped mutate: preserves group keys *)
  let (v, _) = eval_string_env
    {|df |> group_by($dept) |> mutate($x = \(g) 1)|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 5 cols: [name, age, score, dept, x]) grouped by [dept]" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate preserves group keys\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate preserves group keys\n    Expected: DataFrame(5 rows x 5 cols: [name, age, score, dept, x]) grouped by [dept]\n    Got: %s\n" result
  end;

  (* Grouped mutate: compute group mean score *)
  let (v, _) = eval_string_env
    {|result = df |> group_by($dept) |> mutate($mean_score = mean($score)); result.mean_score|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
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
    {|df |> group_by($dept) |> mutate($dept_size = nrow($dept)) |> filter($dept_size > 2) |> nrow|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ grouped mutate chains with filter\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped mutate chains with filter\n    Expected: 3\n    Got: %s\n" result
  end;

  (* Ungrouped mutate *)
  let (v, _) = eval_string_env {|mutate(df, $age_x2 = $age * 2) |> ncol|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "5" then begin
    incr pass_count; Printf.printf "  ✓ ungrouped mutate works\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ ungrouped mutate works\n    Expected: 5\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Phase 4 — Group-by with NAs (golden test repro):\n";

  let csv_nas = "test_nas_groupby.csv" in
  let oc_nas = open_out csv_nas in
  output_string oc_nas "Ozone,Wind,Temp\n";
  output_string oc_nas "41,7.4,67\n";
  output_string oc_nas ",8.0,72\n";
  output_string oc_nas "12,12.6,74\n";
  output_string oc_nas ",14.3,56\n";
  output_string oc_nas "28,14.9,66\n";
  output_string oc_nas "23,8.6,65\n";
  output_string oc_nas "45,14.9,81\n";
  output_string oc_nas "115,5.7,79\n";
  output_string oc_nas "37,7.4,76\n";
  close_out oc_nas;

  let env_nas = Packages.init_env () in
  let (_, env_nas) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_nas) env_nas in

  let step1_result = (try
    let (_, env_n) = eval_string_env
      {|step1 = df |> mutate($temp_category = if ($Temp > 75) "hot" else "cool")|}
      env_nas in
    let (v, _) = eval_string_env "step1" env_n in
    Ok (v, env_n)
  with e -> Error (Printexc.to_string e))
  in
  (match step1_result with
  | Ok (v, env_nas2) ->
    let result = Ast.Utils.value_to_string v in
    if String.length result >= 9 && String.sub result 0 9 = "DataFrame" then begin
      incr pass_count; Printf.printf "  ✓ mutate with if/else on CSV with NAs\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ mutate with if/else on CSV with NAs\n    Got: %s\n" result
    end;

    let step2_result = (try
      let (_, env_n2) = eval_string_env
        {|result = step1 |> group_by($temp_category) |> summarize($mean_ozone = mean($Ozone, na_rm = true), $count = nrow($temp_category))|}
        env_nas2 in
      let (v2, _) = eval_string_env "result" env_n2 in
      Ok v2
    with e -> Error (Printexc.to_string e))
    in
    (match step2_result with
    | Ok v2 ->
      let result2 = Ast.Utils.value_to_string v2 in
      if String.length result2 >= 9 && String.sub result2 0 9 = "DataFrame" then begin
        incr pass_count; Printf.printf "  ✓ grouped summarize with mean on NAs\n"
      end else begin
        incr fail_count; Printf.printf "  ✗ grouped summarize with mean on NAs\n    Got: %s\n" result2
      end
    | Error msg ->
      incr fail_count; Printf.printf "  ✗ grouped summarize with mean on NAs\n    EXCEPTION: %s\n" msg)
  | Error msg ->
    incr fail_count; Printf.printf "  ✗ mutate with if/else on CSV with NAs\n    EXCEPTION: %s\n" msg;
    incr fail_count; Printf.printf "  ✗ grouped summarize with mean on NAs (skipped)\n");

  (try Sys.remove csv_nas with _ -> ());
  print_newline ();

  Printf.printf "Phase 4 — NSE Syntax:\n";

  (* NSE summarize with $col = expr *)
  let (v, _) = eval_string_env {|summarize(df, $total_score = sum($score))|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(1 rows x 1 cols: [total_score])" then begin
    incr pass_count; Printf.printf "  ✓ summarize with $col = expr\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ summarize with $col = expr\n    Expected: DataFrame(1 rows x 1 cols: [total_score])\n    Got: %s\n" result
  end;

  (* Grouped summarize with $col = expr *)
  let (v, _) = eval_string_env {|df |> group_by($dept) |> summarize($avg_score = mean($score))|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(2 rows x 2 cols: [dept, avg_score])" then begin
    incr pass_count; Printf.printf "  ✓ grouped summarize with $col = expr\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped summarize with $col = expr\n    Expected: DataFrame(2 rows x 2 cols: [dept, avg_score])\n    Got: %s\n" result
  end;

  (* NSE mutate: mutate($col = expr) *)
  let (v, _) = eval_string_env {|mutate(df, $age_plus_10 = $age + 10)|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 5 cols: [name, age, score, dept, age_plus_10])" then begin
    incr pass_count; Printf.printf "  ✓ mutate with $col = expr\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ mutate with $col = expr\n    Expected: DataFrame(5 rows x 5 cols: [name, age, score, dept, age_plus_10])\n    Got: %s\n" result
  end;

  test "mutate $col = expr via pipe"
    (Printf.sprintf {|df = read_csv("%s"); df |> mutate($age_x2 = $age * 2) |> ncol|} csv_p4)
    "5";

  (* Full pipeline *)
  test "full NSE pipeline"
    (Printf.sprintf
      {|df = read_csv("%s")
df |> filter($age > 25)
  |> select($name, $score)
  |> arrange($score, "desc")
  |> nrow|} csv_p4)
    "4";

  print_newline ();

  Printf.printf "Phase 4 — complete():\n";

  let env_complete = Packages.init_env () in
  let (_, env_complete) = eval_string_env
    {|df_dates = dataframe([
  [group: "a", d: ymd("2024-01-01"), value: 1],
  [group: "a", d: ymd("2024-01-02"), value: 2],
  [group: "b", d: ymd("2024-01-01"), value: 3]
])|}
    env_complete in

  let (v, env_complete) =
    eval_string_env {|result_dates = complete(df_dates, $group, $d, fill = [value: 0]); nrow(result_dates)|} env_complete in
  let result = Ast.Utils.value_to_string v in
  if result = "4" then begin
    incr pass_count; Printf.printf "  ✓ complete expands date id columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ complete expands date id columns\n    Expected: 4\n    Got: %s\n" result
  end;

  let (v, env_complete) = eval_string_env {|day(result_dates.d)|} env_complete in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 2, 1, 2]" then begin
    incr pass_count; Printf.printf "  ✓ complete preserves date id values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ complete preserves date id values\n    Expected: Vector[1, 2, 1, 2]\n    Got: %s\n" result
  end;

  let (v, env_complete) = eval_string_env {|result_dates.value|} env_complete in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 2, 3, 0]" then begin
    incr pass_count; Printf.printf "  ✓ complete fills missing date combinations\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ complete fills missing date combinations\n    Expected: Vector[1, 2, 3, 0]\n    Got: %s\n" result
  end;

  let (_, env_complete) = eval_string_env
    {|df_datetimes = dataframe([
  [group: "a", ts: ymd_hms("2024-01-01 09:00:00"), value: 1],
  [group: "a", ts: ymd_hms("2024-01-01 10:00:00"), value: 3],
  [group: "b", ts: ymd_hms("2024-01-01 09:00:00"), value: 2]
])|}
    env_complete in

  let (v, env_complete) =
    eval_string_env {|result_datetimes = complete(df_datetimes, $group, $ts, fill = [value: 0]); nrow(result_datetimes)|} env_complete in
  let result = Ast.Utils.value_to_string v in
  if result = "4" then begin
    incr pass_count; Printf.printf "  ✓ complete expands datetime id columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ complete expands datetime id columns\n    Expected: 4\n    Got: %s\n" result
  end;

  let (v, env_complete) = eval_string_env {|hour(result_datetimes.ts)|} env_complete in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[9, 10, 9, 10]" then begin
    incr pass_count; Printf.printf "  ✓ complete preserves datetime id values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ complete preserves datetime id values\n    Expected: Vector[9, 10, 9, 10]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|result_datetimes.value|} env_complete in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 3, 2, 0]" then begin
    incr pass_count; Printf.printf "  ✓ complete fills missing datetime combinations\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ complete fills missing datetime combinations\n    Expected: Vector[1, 3, 2, 0]\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Phase 4 — date/datetime colcraft regressions:\n";

  let env_dates = Packages.init_env () in
  let (_, env_dates) = eval_string_env
    {|df_wider = dataframe([
  [d: ymd("2024-01-01"), name: "x", score: 1],
  [d: ymd("2024-01-01"), name: "y", score: 2],
  [d: ymd("2024-01-02"), name: "x", score: 3],
  [d: ymd("2024-01-02"), name: "y", score: 4]
])|}
    env_dates in
  let (v, env_dates) =
    eval_string_env {|result_wider = pivot_wider(df_wider, names_from = $name, values_from = $score); day(result_wider.d)|} env_dates in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 2]" then begin
    incr pass_count; Printf.printf "  ✓ pivot_wider preserves date id columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pivot_wider preserves date id columns\n    Expected: Vector[1, 2]\n    Got: %s\n" result
  end;

  let (_, env_dates) = eval_string_env
    {|df_longer = dataframe([
  [ts: ymd_hms("2024-01-01 09:00:00"), a: 1, b: 2],
  [ts: ymd_hms("2024-01-01 10:00:00"), a: 3, b: 4]
])|}
    env_dates in
  let (v, env_dates) =
    eval_string_env {|result_longer = pivot_longer(df_longer, $a, $b, names_to = "name", values_to = "value"); hour(result_longer.ts)|} env_dates in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[9, 9, 10, 10]" then begin
    incr pass_count; Printf.printf "  ✓ pivot_longer preserves datetime id columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pivot_longer preserves datetime id columns\n    Expected: Vector[9, 9, 10, 10]\n    Got: %s\n" result
  end;

  let (_, env_dates) = eval_string_env
    {|df_fill = dataframe([
  [d: ymd("2024-01-01")],
  [d: NA],
  [d: ymd("2024-01-03")]
])|}
    env_dates in
  let (v, env_dates) = eval_string_env {|result_fill = fill(df_fill, $d); day(result_fill.d)|} env_dates in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 1, 3]" then begin
    incr pass_count; Printf.printf "  ✓ fill propagates date values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ fill propagates date values\n    Expected: Vector[1, 1, 3]\n    Got: %s\n" result
  end;

  let (_, env_dates) = eval_string_env
    {|df_replace = dataframe([
  [d: ymd("2024-01-01"), ts: ymd_hms("2024-01-01 09:00:00")],
  [d: NA, ts: NA]
])|}
    env_dates in
  let (v, env_dates) =
    eval_string_env {|result_replace = replace_na(df_replace, [d: ymd("2024-01-02"), ts: ymd_hms("2024-01-01 10:00:00")]); day(result_replace.d)|} env_dates in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 2]" then begin
    incr pass_count; Printf.printf "  ✓ replace_na fills date columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ replace_na fills date columns\n    Expected: Vector[1, 2]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|hour(result_replace.ts)|} env_dates in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[9, 10]" then begin
    incr pass_count; Printf.printf "  ✓ replace_na fills datetime columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ replace_na fills datetime columns\n    Expected: Vector[9, 10]\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Phase 4 — joins, binders, and extended selectors:\n";

  test "left_join keeps left rows"
    {|left = dataframe([[id: 1, x: "a"], [id: 2, x: "b"]]); right = dataframe([[id: 2, y: "two"], [id: 3, y: "three"]]); left_join(left, right, by = $id) |> nrow|}
    "2";
  test "left_join fills unmatched with NA"
    {|left = dataframe([[id: 1, x: "a"], [id: 2, x: "b"]]); right = dataframe([[id: 2, y: "two"], [id: 3, y: "three"]]); left_join(left, right, by = $id).y|}
    {|Vector[NA(String), "two"]|};
  test "inner_join keeps matches only"
    {|left = dataframe([[id: 1, x: "a"], [id: 2, x: "b"]]); right = dataframe([[id: 2, y: "two"], [id: 3, y: "three"]]); inner_join(left, right, by = $id) |> nrow|}
    "1";
  test "full_join includes unmatched right rows"
    {|left = dataframe([[id: 1, x: "a"], [id: 2, x: "b"]]); right = dataframe([[id: 2, y: "two"], [id: 3, y: "three"]]); full_join(left, right, by = $id).id|}
    "Vector[1, 2, 3]";
  test "semi_join filters left rows by match"
    {|left = dataframe([[id: 1, x: "a"], [id: 2, x: "b"]]); right = dataframe([[id: 2, y: "two"], [id: 3, y: "three"]]); semi_join(left, right, by = $id).x|}
    {|Vector["b"]|};
  test "semi_join keeps only left columns"
    {|left = dataframe([[id: 1, x: "a"], [id: 2, x: "b"]]); right = dataframe([[id: 2, y: "two"], [id: 3, y: "three"]]); semi_join(left, right, by = $id) |> ncol|}
    "2";
  test "anti_join filters left rows without match"
    {|left = dataframe([[id: 1, x: "a"], [id: 2, x: "b"]]); right = dataframe([[id: 2, y: "two"], [id: 3, y: "three"]]); anti_join(left, right, by = $id).x|}
    {|Vector["a"]|};
  test "anti_join keeps only left columns"
    {|left = dataframe([[id: 1, x: "a"], [id: 2, x: "b"]]); right = dataframe([[id: 2, y: "two"], [id: 3, y: "three"]]); anti_join(left, right, by = $id) |> ncol|}
    "2";
  test "bind_rows unions columns"
    {|bind_rows(dataframe([[id: 1, x: "a"]]), dataframe([[id: 2, y: "b"]])) |> ncol|}
    "3";
  test "bind_rows fills missing columns"
    {|bind_rows(dataframe([[id: 1, x: "a"]]), dataframe([[id: 2, y: "b"]])).y|}
    {|Vector[NA(String), "b"]|};
  test "bind_cols combines columns"
    {|bind_cols(dataframe([[id: 1], [id: 2]]), dataframe([[value: "a"], [value: "b"]])).value|}
    {|Vector["a", "b"]|};
  test "unite na_rm removes missing values"
    {|unite(dataframe([[x: "a", y: NA], [x: NA, y: "b"]]), "xy", $x, $y, na_rm = true).xy|}
    {|Vector["a", "b"]|};
  test "select where numeric columns"
    {|wide = dataframe([[name: "Alice", age: 30, score: 95.5, dept: "eng"]]); select(wide, where(is_numeric)) |> ncol|}
    "2";
  test "select matches regex"
    {|wide = dataframe([[name: "Alice", age: 30, score: 95.5, dept: "eng"]]); select(wide, matches("^s")) |> ncol|}
    "1";
  test "select all_of names"
    {|wide = dataframe([[name: "Alice", age: 30, score: 95.5, dept: "eng"]]); select(wide, all_of(["name", "score"])) |> ncol|}
    "2";
  test "select any_of ignores missing names"
    {|wide = dataframe([[name: "Alice", age: 30, score: 95.5, dept: "eng"]]); select(wide, any_of(["name", "missing"])) |> ncol|}
    "1";
  test "fct_lump_min groups infrequent levels"
    {|levels(fct_lump_min(fct(["a", "a", "b", "c"]), 2))|}
    {|Vector["a", "Other"]|};
  test "fct_other keeps selected levels"
    {|levels(fct_other(fct(["a", "b", "c"]), keep = ["a"]))|}
    {|Vector["a", "Other"]|};
  test "fct_drop removes unused levels"
    {|levels(fct_drop(factor(["a", "b"], levels = ["a", "b", "c"])))|}
    {|Vector["a", "b"]|};
  test "fct_expand adds levels"
    {|levels(fct_expand(fct(["a"]), "b", "c"))|}
    {|Vector["a", "b", "c"]|};
  test "fct_c unifies levels"
    {|levels(fct_c(fct(["a"], levels = ["a", "b"]), fct(["c"])))|}
    {|Vector["a", "b", "c"]|};

  print_newline ();

  Printf.printf "Phase 4 — Vectorized Processing:\n";

  (* Vectorized ungrouped summarize with mean *)
  let (v, _) = eval_string_env {|summarize(df, $avg_score = mean($score))|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(1 rows x 1 cols: [avg_score])" then begin
    incr pass_count; Printf.printf "  ✓ vectorized ungrouped summarize mean\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ vectorized ungrouped summarize mean\n    Expected: DataFrame(1 rows x 1 cols: [avg_score])\n    Got: %s\n" result
  end;

  (* Vectorized ungrouped summarize with sum *)
  let (v, _) = eval_string_env {|summarize(df, $total_score = sum($score))|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(1 rows x 1 cols: [total_score])" then begin
    incr pass_count; Printf.printf "  ✓ vectorized ungrouped summarize sum\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ vectorized ungrouped summarize sum\n    Expected: DataFrame(1 rows x 1 cols: [total_score])\n    Got: %s\n" result
  end;

  (* Vectorized ungrouped summarize with min/max *)
  let (v, _) = eval_string_env {|result = summarize(df, $min_age = min($age), $max_age = max($age)); result.min_age|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[25.]" then begin
    incr pass_count; Printf.printf "  ✓ vectorized ungrouped summarize min/max produces correct min\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ vectorized ungrouped summarize min/max produces correct min\n    Expected: Vector[25.]\n    Got: %s\n" result
  end;

  (* Vectorized grouped summarize with mean *)
  let (v, _) = eval_string_env
    {|result = df |> group_by($dept) |> summarize($avg_score = mean($score)); result.avg_score|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  let contains s sub =
    let slen = String.length s in
    let sublen = String.length sub in
    let rec chk i = if i > slen - sublen then false
      else if String.sub s i sublen = sub then true else chk (i + 1)
    in chk 0
  in
  if contains result "93.03333" && contains result "87.65" then begin
    incr pass_count; Printf.printf "  ✓ vectorized grouped summarize mean produces correct values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ vectorized grouped summarize mean produces correct values\n    Expected eng ~93.03 and sales ~87.65\n    Got: %s\n" result
  end;

  (* Vectorized grouped summarize with sum *)
  let (v, _) = eval_string_env
    {|df |> group_by($dept) |> summarize($total_score = sum($score))|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(2 rows x 2 cols: [dept, total_score])" then begin
    incr pass_count; Printf.printf "  ✓ vectorized grouped summarize sum\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ vectorized grouped summarize sum\n    Expected: DataFrame(2 rows x 2 cols: [dept, total_score])\n    Got: %s\n" result
  end;

  (* Vectorized mutate: column-scalar addition *)
  let (v, _) = eval_string_env {|result = mutate(df, $age_plus_5 = $age + 5); result.age_plus_5|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[35, 30, 40, 33, 37]" then begin
    incr pass_count; Printf.printf "  ✓ vectorized mutate column + scalar\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ vectorized mutate column + scalar\n    Expected: Vector[35, 30, 40, 33, 37]\n    Got: %s\n" result
  end;

  (* Vectorized mutate: column-scalar multiplication *)
  let (v, _) = eval_string_env {|result = mutate(df, $age_x2 = $age * 2); result.age_x2|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[60, 50, 70, 56, 64]" then begin
    incr pass_count; Printf.printf "  ✓ vectorized mutate column * scalar\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ vectorized mutate column * scalar\n    Expected: Vector[60, 50, 70, 56, 64]\n    Got: %s\n" result
  end;

  (* Vectorized mutate: column-to-column multiplication *)
  let (v, _) = eval_string_env {|result = mutate(df, $age_score = $age * $score); ncol(result)|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "5" then begin
    incr pass_count; Printf.printf "  ✓ vectorized mutate column * column\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ vectorized mutate column * column\n    Expected: 5\n    Got: %s\n" result
  end;

  (* Vectorized filter: compound AND predicate *)
  let (v, _) = eval_string_env {|df |> filter($age > 25 && $score > 90) |> nrow|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ vectorized filter with AND predicate\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ vectorized filter with AND predicate\n    Expected: 3\n    Got: %s\n" result
  end;

  (* Vectorized filter: compound OR predicate *)
  let (v, _) = eval_string_env {|df |> filter($age < 26 || $score > 95) |> nrow|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ vectorized filter with OR predicate\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ vectorized filter with OR predicate\n    Expected: 2\n    Got: %s\n" result
  end;

  (* Mixed vectorized + non-vectorized summarize *)
  let (v, _) = eval_string_env
    {|summarize(df, $avg_score = mean($score), $total_rows = nrow(df))|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(1 rows x 2 cols: [avg_score, total_rows])" then begin
    incr pass_count; Printf.printf "  ✓ mixed vectorized + non-vectorized summarize\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ mixed vectorized + non-vectorized summarize\n    Expected: DataFrame(1 rows x 2 cols: [avg_score, total_rows])\n    Got: %s\n" result
  end;

  print_newline ();

  (* Clean up Phase 4 CSV *)
  (try Sys.remove csv_p4 with _ -> ())
