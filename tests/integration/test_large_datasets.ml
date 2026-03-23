let run_tests pass_count fail_count _eval_string eval_string_env _test =
  (* === Large Dataset Scenarios === *)

  Printf.printf "Large Datasets — Programmatic CSV generation and operations:\n";

  (* Generate a 1000-row CSV *)
  let csv_large = "test_large_dataset.csv" in
  let oc = open_out csv_large in
  output_string oc "id,group,value\n";
  for i = 1 to 1000 do
    Printf.fprintf oc "%d,%s,%d\n" i
      (if i mod 3 = 0 then "C" else if i mod 2 = 0 then "B" else "A")
      (i * 10)
  done;
  close_out oc;

  (* Initialize environment *)
  let env0 = Packages.init_env () in
  let (_, env0) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_large) env0 in

  (* Verify row count *)
  let (v, _) = eval_string_env {|nrow(df)|} env0 in
  let result = Ast.Utils.value_to_string v in
  if result = "1000" then begin
    incr pass_count; Printf.printf "  ✓ read 1000-row CSV correctly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read 1000-row CSV correctly\n    Expected: 1000\n    Got: %s\n" result
  end;

  (* Verify column count *)
  let (v, _) = eval_string_env {|ncol(df)|} env0 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ 1000-row CSV has 3 columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ 1000-row CSV has 3 columns\n    Expected: 3\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Large Datasets — Filter + select on 1000 rows:\n";

  let (v, _) = eval_string_env
    {|df |> filter($group == "A") |> nrow|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  (* group A: i where i mod 3 != 0 and i mod 2 != 0 -> odd and not divisible by 3 *)
  (* These are: 1,5,7,11,13,17,19,... i.e., numbers not divisible by 2 or 3 *)
  let expected_a = ref 0 in
  for i = 1 to 1000 do
    if i mod 3 <> 0 && i mod 2 <> 0 then incr expected_a
  done;
  if result = string_of_int !expected_a then begin
    incr pass_count; Printf.printf "  ✓ filter group A gives correct count (%d)\n" !expected_a
  end else begin
    incr fail_count; Printf.printf "  ✗ filter group A gives correct count\n    Expected: %d\n    Got: %s\n" !expected_a result
  end;

  (* Select subset of columns *)
  let (v, _) = eval_string_env
    {|df |> select($id, $group) |> ncol|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ select 2 columns from large dataset\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ select 2 columns from large dataset\n    Expected: 2\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Large Datasets — Group by with multiple groups:\n";

  let (v, _) = eval_string_env
    {|df |> group_by($group) |> summarize($count = nrow($group))|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  if String.length result >= 9 && String.sub result 0 9 = "DataFrame" then begin
    incr pass_count; Printf.printf "  ✓ group_by on 1000-row dataset produces DataFrame\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ group_by on 1000-row dataset produces DataFrame\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Large Datasets — Multi-stage pipeline on large data:\n";

  let (v, _) = eval_string_env
    {|df |> filter($value > 100) |> select($id, $group) |> nrow|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  (* value > 100 means i * 10 > 100, i.e., i > 10, so rows 11-1000 = 990 rows *)
  if result = "990" then begin
    incr pass_count; Printf.printf "  ✓ multi-stage pipeline: filter + select on large data\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ multi-stage pipeline: filter + select on large data\n    Expected: 990\n    Got: %s\n" result
  end;

  (* Mutate on large dataset *)
  let (v, _) = eval_string_env
    {|df |> mutate($doubled = $value * 2) |> ncol|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  if result = "4" then begin
    incr pass_count; Printf.printf "  ✓ mutate adds column to large dataset\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ mutate adds column to large dataset\n    Expected: 4\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Large Datasets — Arrange on large data:\n";

  let (v, _) = eval_string_env
    {|df |> arrange($value, "desc") |> nrow|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  if result = "1000" then begin
    incr pass_count; Printf.printf "  ✓ arrange desc on large dataset preserves row count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ arrange desc on large dataset preserves row count\n    Expected: 1000\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Large Datasets — Grouped summarize with sum:\n";

  let (v, _) = eval_string_env
    {|result = df |> group_by($group) |> summarize($total = sum($value)); result.total|}
    env0 in
  let result = Ast.Utils.value_to_string v in
  (* Just verify it produces a vector, not crash *)
  let starts_with s prefix =
    String.length s >= String.length prefix &&
    String.sub s 0 (String.length prefix) = prefix
  in
  if starts_with result "Vector[" then begin
    incr pass_count; Printf.printf "  ✓ grouped summarize sum on large dataset returns Vector\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped summarize sum on large dataset returns Vector\n    Got: %s\n" result
  end;

  (* Clean up *)
  (try Sys.remove csv_large with _ -> ());
  print_newline ();

  Printf.printf "Large Datasets — Many groups:\n";

  (* Generate a dataset with many unique groups *)
  let csv_many = "test_many_groups.csv" in
  let oc2 = open_out csv_many in
  output_string oc2 "id,value\n";
  for i = 1 to 200 do
    Printf.fprintf oc2 "%d,%d\n" i (i * 5)
  done;
  close_out oc2;

  let env2 = Packages.init_env () in
  let (_, env2) = eval_string_env (Printf.sprintf {|df2 = read_csv("%s")|} csv_many) env2 in

  (* group_by unique ids — 200 groups of 1 row each *)
  let (v, _) = eval_string_env
    {|df2 |> group_by($id) |> summarize($count = nrow($id)) |> nrow|}
    env2 in
  let result = Ast.Utils.value_to_string v in
  if result = "200" then begin
    incr pass_count; Printf.printf "  ✓ 200 unique groups produces 200-row summary\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ 200 unique groups produces 200-row summary\n    Expected: 200\n    Got: %s\n" result
  end;

  (try Sys.remove csv_many with _ -> ());
  print_newline ()
