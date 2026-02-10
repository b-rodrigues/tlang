let run_tests pass_count fail_count _eval_string eval_string_env test =
  (* Create test CSV file for Phase 2 tests *)
  let csv_path = "test_phase2.csv" in
  let oc = open_out csv_path in
  output_string oc "name,age,score\nAlice,30,95.5\nBob,25,87.3\nCharlie,35,92.1\n";
  close_out oc;

  let csv_path_types = "test_phase2_types.csv" in
  let oc2 = open_out csv_path_types in
  output_string oc2 "id,active,value\n1,true,3.14\n2,false,2.71\n3,true,1.41\n";
  close_out oc2;

  let csv_path_na = "test_phase2_na.csv" in
  let oc3 = open_out csv_path_na in
  output_string oc3 "x,y\n1,hello\nNA,world\n3,NA\n";
  close_out oc3;

  let csv_path_empty = "test_phase2_empty.csv" in
  let oc4 = open_out csv_path_empty in
  output_string oc4 "a,b,c\n";
  close_out oc4;

  Printf.printf "Phase 2 — read_csv():\n";
  (* Use shared env for multi-step DataFrame tests *)
  let env = Eval.initial_env () in
  let (_, env) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_path) env in
  let (v, _) = eval_string_env "type(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = {|"DataFrame"|} then begin
    incr pass_count; Printf.printf "  ✓ read_csv returns DataFrame\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read_csv returns DataFrame\n    Expected: \"DataFrame\"\n    Got: %s\n" result
  end;

  test "read_csv with missing file"
    {|read_csv("nonexistent_file.csv")|}
    {|Error(FileError: "File Error: nonexistent_file.csv: No such file or directory")|};
  test "read_csv with non-string arg"
    "read_csv(42)"
    {|Error(TypeError: "read_csv() expects a String path")|};
  test "read_csv with NA arg"
    "read_csv(NA)"
    {|Error(TypeError: "read_csv() expects a String path, got NA")|};
  print_newline ();

  Printf.printf "Phase 2 — nrow() and ncol():\n";
  let (v, _) = eval_string_env "nrow(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ nrow returns correct count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ nrow returns correct count\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "ncol(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ ncol returns correct count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ ncol returns correct count\n    Expected: 3\n    Got: %s\n" result
  end;

  test "nrow on non-DataFrame"
    "nrow(42)"
    {|Error(TypeError: "nrow() expects a DataFrame")|};
  test "ncol on non-DataFrame"
    "ncol([1, 2, 3])"
    {|Error(TypeError: "ncol() expects a DataFrame")|};
  test "nrow on NA"
    "nrow(NA)"
    {|Error(TypeError: "nrow() expects a DataFrame, got NA")|};
  print_newline ();

  Printf.printf "Phase 2 — colnames():\n";
  let (v, _) = eval_string_env "colnames(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  ✓ colnames returns column names\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ colnames returns column names\n    Expected: [\"name\", \"age\", \"score\"]\n    Got: %s\n" result
  end;

  test "colnames on non-DataFrame"
    {|colnames("hello")|}
    {|Error(TypeError: "colnames() expects a DataFrame")|};
  print_newline ();

  Printf.printf "Phase 2 — Column Access (dot notation):\n";
  let (v, _) = eval_string_env "df.name" env in
  let result = Ast.Utils.value_to_string v in
  if result = {|Vector["Alice", "Bob", "Charlie"]|} then begin
    incr pass_count; Printf.printf "  ✓ column access by name returns Vector\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ column access by name returns Vector\n    Expected: Vector[\"Alice\", \"Bob\", \"Charlie\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "df.age" env in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[30, 25, 35]" then begin
    incr pass_count; Printf.printf "  ✓ numeric column access returns typed values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ numeric column access returns typed values\n    Expected: Vector[30, 25, 35]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "df.score" env in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[95.5, 87.3, 92.1]" then begin
    incr pass_count; Printf.printf "  ✓ float column access returns typed values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ float column access returns typed values\n    Expected: Vector[95.5, 87.3, 92.1]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "df.nonexistent" env in
  let result = Ast.Utils.value_to_string v in
  if result = {|Error(KeyError: "column 'nonexistent' not found in DataFrame")|} then begin
    incr pass_count; Printf.printf "  ✓ missing column returns error\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ missing column returns error\n    Expected: Error(KeyError: ...)\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — DataFrame Type Inference:\n";
  let (_, env2) = eval_string_env (Printf.sprintf {|df2 = read_csv("%s")|} csv_path_types) env in
  let (v, _) = eval_string_env "df2.id" env2 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 2, 3]" then begin
    incr pass_count; Printf.printf "  ✓ integer columns inferred correctly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ integer columns inferred correctly\n    Expected: Vector[1, 2, 3]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "df2.active" env2 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[true, false, true]" then begin
    incr pass_count; Printf.printf "  ✓ boolean columns inferred correctly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ boolean columns inferred correctly\n    Expected: Vector[true, false, true]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "df2.value" env2 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[3.14, 2.71, 1.41]" then begin
    incr pass_count; Printf.printf "  ✓ float columns inferred correctly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ float columns inferred correctly\n    Expected: Vector[3.14, 2.71, 1.41]\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — NA in CSV:\n";
  let (_, env3) = eval_string_env (Printf.sprintf {|df3 = read_csv("%s")|} csv_path_na) env in
  let (v, _) = eval_string_env "df3.x" env3 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, NA(Int), 3]" then begin
    incr pass_count; Printf.printf "  ✓ NA values preserved in CSV import\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ NA values preserved in CSV import\n    Expected: Vector[1, NA(Int), 3]\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — Empty DataFrame:\n";
  let (_, env4) = eval_string_env (Printf.sprintf {|df4 = read_csv("%s")|} csv_path_empty) env in
  let (v, _) = eval_string_env "nrow(df4)" env4 in
  let result = Ast.Utils.value_to_string v in
  if result = "0" then begin
    incr pass_count; Printf.printf "  ✓ empty CSV has 0 rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ empty CSV has 0 rows\n    Expected: 0\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "ncol(df4)" env4 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ empty CSV retains column count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ empty CSV retains column count\n    Expected: 3\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — DataFrame in Pipelines:\n";
  let (v, _) = eval_string_env (Printf.sprintf {|read_csv("%s") |> nrow|} csv_path) env in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ DataFrame works as pipeline input (nrow)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ DataFrame works as pipeline input (nrow)\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env (Printf.sprintf {|read_csv("%s") |> colnames|} csv_path) env in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  ✓ DataFrame works as pipeline input (colnames)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ DataFrame works as pipeline input (colnames)\n    Expected: [\"name\", \"age\", \"score\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env (Printf.sprintf {|read_csv("%s") |> ncol|} csv_path) env in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ DataFrame works as pipeline input (ncol)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ DataFrame works as pipeline input (ncol)\n    Expected: 3\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — DataFrame Display:\n";
  let (v, _) = eval_string_env "df" env in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(3 rows x 3 cols: [name, age, score])" then begin
    incr pass_count; Printf.printf "  ✓ DataFrame display format correct\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ DataFrame display format correct\n    Expected: DataFrame(3 rows x 3 cols: [name, age, score])\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — Immutability:\n";
  test "type of DataFrame"
    (Printf.sprintf {|type(read_csv("%s"))|} csv_path)
    {|"DataFrame"|};
  print_newline ();

  (* Phase 5 — read_csv() with optional arguments *)
  Printf.printf "Phase 5 — read_csv() optional arguments:\n";

  let csv_path_sep = "test_phase5_sep.csv" in
  let oc5 = open_out csv_path_sep in
  output_string oc5 "name;age;score\nAlice;30;95.5\nBob;25;87.3\n";
  close_out oc5;

  let csv_path_skip = "test_phase5_skip.csv" in
  let oc6 = open_out csv_path_skip in
  output_string oc6 "# This is a comment\n# Another comment\nname,age,score\nAlice,30,95.5\nBob,25,87.3\n";
  close_out oc6;

  let csv_path_noheader = "test_phase5_noheader.csv" in
  let oc7 = open_out csv_path_noheader in
  output_string oc7 "Alice,30,95.5\nBob,25,87.3\n";
  close_out oc7;

  (* Test read_csv with sep *)
  let env5 = Eval.initial_env () in
  let (_, env5) = eval_string_env (Printf.sprintf {|df = read_csv("%s", sep = ";")|} csv_path_sep) env5 in
  let (v, _) = eval_string_env "nrow(df)" env5 in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ read_csv with sep=\";\" reads correct rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read_csv with sep=\";\" reads correct rows\n    Expected: 2\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "colnames(df)" env5 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  ✓ read_csv with sep=\";\" reads correct columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read_csv with sep=\";\" reads correct columns\n    Expected: [\"name\", \"age\", \"score\"]\n    Got: %s\n" result
  end;

  (* Test read_csv with skip_lines *)
  let env6 = Eval.initial_env () in
  let (_, env6) = eval_string_env (Printf.sprintf {|df = read_csv("%s", skip_lines = 2)|} csv_path_skip) env6 in
  let (v, _) = eval_string_env "nrow(df)" env6 in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ read_csv with skip_lines=2 skips comment lines\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read_csv with skip_lines=2 skips comment lines\n    Expected: 2\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "colnames(df)" env6 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  ✓ read_csv with skip_lines=2 reads correct header\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read_csv with skip_lines=2 reads correct header\n    Expected: [\"name\", \"age\", \"score\"]\n    Got: %s\n" result
  end;

  (* Test read_csv with skip_header *)
  let env7 = Eval.initial_env () in
  let (_, env7) = eval_string_env (Printf.sprintf {|df = read_csv("%s", skip_header = true)|} csv_path_noheader) env7 in
  let (v, _) = eval_string_env "nrow(df)" env7 in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ read_csv with skip_header=true reads all lines as data\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read_csv with skip_header=true reads all lines as data\n    Expected: 2\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "colnames(df)" env7 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["V1", "V2", "V3"]|} then begin
    incr pass_count; Printf.printf "  ✓ read_csv with skip_header=true generates V1,V2,V3 column names\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read_csv with skip_header=true generates V1,V2,V3 column names\n    Expected: [\"V1\", \"V2\", \"V3\"]\n    Got: %s\n" result
  end;
  print_newline ();

  (* Phase 5 — write_csv() with optional arguments *)
  Printf.printf "Phase 5 — write_csv() optional arguments:\n";

  let csv_out_sep = "test_phase5_write_sep.csv" in
  let env_w = Eval.initial_env () in
  let (_, env_w) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_path) env_w in
  let (v, _) = eval_string_env (Printf.sprintf {|write_csv(df, "%s", sep = ";")|} csv_out_sep) env_w in
  let result = Ast.Utils.value_to_string v in
  if result = "null" then begin
    incr pass_count; Printf.printf "  ✓ write_csv with sep=\";\" returns null\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ write_csv with sep=\";\" returns null\n    Expected: null\n    Got: %s\n" result
  end;

  (* Roundtrip: read back the semicolon-separated file *)
  let (_, env_w2) = eval_string_env (Printf.sprintf {|df2 = read_csv("%s", sep = ";")|} csv_out_sep) env_w in
  let (v, _) = eval_string_env "nrow(df2)" env_w2 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ roundtrip with sep=\";\" preserves row count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ roundtrip with sep=\";\" preserves row count\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "colnames(df2)" env_w2 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  ✓ roundtrip with sep=\";\" preserves column names\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ roundtrip with sep=\";\" preserves column names\n    Expected: [\"name\", \"age\", \"score\"]\n    Got: %s\n" result
  end;
  print_newline ();

  (* Clean up test CSV files *)
  (try Sys.remove csv_path with _ -> ());
  (try Sys.remove csv_path_types with _ -> ());
  (try Sys.remove csv_path_na with _ -> ());
  (try Sys.remove csv_path_empty with _ -> ());
  (try Sys.remove csv_path_sep with _ -> ());
  (try Sys.remove csv_path_skip with _ -> ());
  (try Sys.remove csv_path_noheader with _ -> ());
  (try Sys.remove csv_out_sep with _ -> ())
