let run_tests _pass_count _fail_count _failures _eval_string eval_string_env _test test_env =
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
  let env0 = Test_helpers.eval_setup eval_string_env env0 "test_large_datasets:19" (Printf.sprintf {|df = read_csv("%s")|} csv_large) in

  test_env env0 "read 1000-row CSV correctly"
    {|nrow(df)|}
    "1000";

  test_env env0 "1000-row CSV has 3 columns"
    {|ncol(df)|}
    "3";

  print_newline ();

  Printf.printf "Large Datasets — Filter + select on 1000 rows:\n";

  (* group A: i where i mod 3 != 0 and i mod 2 != 0 -> odd and not divisible by 3 *)
  let expected_a = ref 0 in
  for i = 1 to 1000 do
    if i mod 3 <> 0 && i mod 2 <> 0 then incr expected_a
  done;

  test_env env0 "filter group A gives correct count"
    {|df |> filter($group == "A") |> nrow|}
    (string_of_int !expected_a);

  test_env env0 "select 2 columns from large dataset"
    {|df |> select($id, $group) |> ncol|}
    "2";

  print_newline ();

  Printf.printf "Large Datasets — Group by with multiple groups:\n";

  test_env env0 "group_by on 1000-row dataset produces DataFrame"
    {|df |> group_by($group) |> summarize($count = nrow($group))|}
    "DataFrame";

  print_newline ();

  Printf.printf "Large Datasets — Multi-stage pipeline on large data:\n";

  (* value > 100 means i * 10 > 100, i.e., i > 10, so rows 11-1000 = 990 rows *)
  test_env env0 "multi-stage pipeline: filter + select on large data"
    {|df |> filter($value > 100) |> select($id, $group) |> nrow|}
    "990";

  test_env env0 "mutate adds column to large dataset"
    {|df |> mutate($doubled = $value * 2) |> ncol|}
    "4";

  print_newline ();

  Printf.printf "Large Datasets — Arrange on large data:\n";

  test_env env0 "arrange desc on large dataset preserves row count"
    {|df |> arrange($value, "desc") |> nrow|}
    "1000";

  print_newline ();

  Printf.printf "Large Datasets — Grouped summarize with sum:\n";

  test_env env0 "grouped summarize sum on large dataset returns Vector"
    {|result = df |> group_by($group) |> summarize($total = sum($value)); result.total|}
    "Vector[";

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
  let env2 = Test_helpers.eval_setup eval_string_env env2 "test_large_datasets:100" (Printf.sprintf {|df2 = read_csv("%s")|} csv_many) in

  test_env env2 "200 unique groups produces 200-row summary"
    {|df2 |> group_by($id) |> summarize($count = nrow($id)) |> nrow|}
    "200";

  (try Sys.remove csv_many with _ -> ());
  print_newline ()
