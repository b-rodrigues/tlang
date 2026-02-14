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
    {|Error(FileError: "File Error: nonexistent_file.csv: No such file or directory.")|};
  test "read_csv with non-string arg"
    "read_csv(42)"
    {|Error(TypeError: "Function `read_csv` expects a String path.")|};
  test "read_csv with NA arg"
    "read_csv(NA)"
    {|Error(TypeError: "Function `read_csv` expects a String path, got NA.")|};
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
    {|Error(TypeError: "Function `nrow` expects a DataFrame or vector.")|};
  test "ncol on non-DataFrame"
    "ncol([1, 2, 3])"
    {|Error(TypeError: "Function `ncol` expects a DataFrame.")|};
  test "nrow on NA"
    "nrow(NA)"
    {|Error(TypeError: "Function `nrow` expects a DataFrame or vector, got NA.")|};
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
    {|Error(TypeError: "Function `colnames` expects a DataFrame.")|};
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
  if result = {|Error(KeyError: "Column `nonexistent` not found in DataFrame.")|} then begin
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

  (* Test read_csv with separator *)
  let env5 = Eval.initial_env () in
  let (_, env5) = eval_string_env (Printf.sprintf {|df = read_csv("%s", separator = ";")|} csv_path_sep) env5 in
  let (v, _) = eval_string_env "nrow(df)" env5 in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ read_csv with separator=\";\" reads correct rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read_csv with separator=\";\" reads correct rows\n    Expected: 2\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "colnames(df)" env5 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  ✓ read_csv with separator=\";\" reads correct columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read_csv with separator=\";\" reads correct columns\n    Expected: [\"name\", \"age\", \"score\"]\n    Got: %s\n" result
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
  let (v, _) = eval_string_env (Printf.sprintf {|write_csv(df, "%s", separator = ";")|} csv_out_sep) env_w in
  let result = Ast.Utils.value_to_string v in
  if result = "null" then begin
    incr pass_count; Printf.printf "  ✓ write_csv with separator=\";\" returns null\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ write_csv with separator=\";\" returns null\n    Expected: null\n    Got: %s\n" result
  end;

  (* Roundtrip: read back the semicolon-separated file *)
  let (_, env_w2) = eval_string_env (Printf.sprintf {|df2 = read_csv("%s", separator = ";")|} csv_out_sep) env_w in
  let (v, _) = eval_string_env "nrow(df2)" env_w2 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ roundtrip with separator=\";\" preserves row count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ roundtrip with separator=\";\" preserves row count\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "colnames(df2)" env_w2 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  ✓ roundtrip with separator=\";\" preserves column names\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ roundtrip with separator=\";\" preserves column names\n    Expected: [\"name\", \"age\", \"score\"]\n    Got: %s\n" result
  end;
  print_newline ();

  (* ================================================================= *)
  (* clean_colnames tests                                               *)
  (* ================================================================= *)
  Printf.printf "Phase — read_csv() with clean_colnames:\n";

  (* Test CSV with symbols in column names *)
  let csv_path_symbols = "test_clean_symbols.csv" in
  let oc_s = open_out csv_path_symbols in
  output_string oc_s "growth%,MILLION\xe2\x82\xac,price$\n10,500,42\n";
  close_out oc_s;

  let env_c1 = Eval.initial_env () in
  let (_, env_c1) = eval_string_env (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_symbols) env_c1 in
  let (v, _) = eval_string_env "colnames(df)" env_c1 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["growth_percent", "million_euro", "price_dollar"]|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 clean_colnames expands symbols\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 clean_colnames expands symbols\n    Expected: [\"growth_percent\", \"million_euro\", \"price_dollar\"]\n    Got: %s\n" result
  end;

  (* Test CSV with punctuation in column names *)
  let csv_path_punct = "test_clean_punct.csv" in
  let oc_p = open_out csv_path_punct in
  output_string oc_p "A.1,foo---bar,hello world\n1,2,3\n";
  close_out oc_p;

  let env_c2 = Eval.initial_env () in
  let (_, env_c2) = eval_string_env (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_punct) env_c2 in
  let (v, _) = eval_string_env "colnames(df)" env_c2 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["a_1", "foo_bar", "hello_world"]|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 clean_colnames handles punctuation\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 clean_colnames handles punctuation\n    Expected: [\"a_1\", \"foo_bar\", \"hello_world\"]\n    Got: %s\n" result
  end;

  (* Test CSV with Unicode diacritics *)
  let csv_path_unicode = "test_clean_unicode.csv" in
  let oc_u = open_out csv_path_unicode in
  output_string oc_u "caf\xc3\xa9,na\xc3\xafve\n1,2\n";
  close_out oc_u;

  let env_c3 = Eval.initial_env () in
  let (_, env_c3) = eval_string_env (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_unicode) env_c3 in
  let (v, _) = eval_string_env "colnames(df)" env_c3 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["cafe", "naive"]|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 clean_colnames strips diacritics\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 clean_colnames strips diacritics\n    Expected: [\"cafe\", \"naive\"]\n    Got: %s\n" result
  end;

  (* Test collision resolution *)
  let csv_path_collide = "test_clean_collide.csv" in
  let oc_co = open_out csv_path_collide in
  output_string oc_co "A.1,A-1,A_1\n1,2,3\n";
  close_out oc_co;

  let env_c4 = Eval.initial_env () in
  let (_, env_c4) = eval_string_env (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_collide) env_c4 in
  let (v, _) = eval_string_env "colnames(df)" env_c4 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["a_1", "a_1_2", "a_1_3"]|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 clean_colnames resolves collisions\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 clean_colnames resolves collisions\n    Expected: [\"a_1\", \"a_1_2\", \"a_1_3\"]\n    Got: %s\n" result
  end;

  (* Test digit-prefixed names *)
  let csv_path_digits = "test_clean_digits.csv" in
  let oc_d = open_out csv_path_digits in
  output_string oc_d "1st,2nd_col,normal\n1,2,3\n";
  close_out oc_d;

  let env_c5 = Eval.initial_env () in
  let (_, env_c5) = eval_string_env (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_digits) env_c5 in
  let (v, _) = eval_string_env "colnames(df)" env_c5 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["x_1st", "x_2nd_col", "normal"]|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 clean_colnames prefixes digit-leading names\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 clean_colnames prefixes digit-leading names\n    Expected: [\"x_1st\", \"x_2nd_col\", \"normal\"]\n    Got: %s\n" result
  end;

  (* Test clean_colnames = false preserves original names *)
  let env_c6 = Eval.initial_env () in
  let (_, env_c6) = eval_string_env (Printf.sprintf {|df = read_csv("%s", clean_colnames = false)|} csv_path_punct) env_c6 in
  let (v, _) = eval_string_env "colnames(df)" env_c6 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["A.1", "foo---bar", "hello world"]|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 clean_colnames = false preserves original names\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 clean_colnames = false preserves original names\n    Expected: [\"A.1\", \"foo---bar\", \"hello world\"]\n    Got: %s\n" result
  end;

  (* Test standalone clean_colnames() on a DataFrame *)
  let env_c7 = Eval.initial_env () in
  let (_, env_c7) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_path_punct) env_c7 in
  let (_, env_c7) = eval_string_env "df2 = clean_colnames(df)" env_c7 in
  let (v, _) = eval_string_env "colnames(df2)" env_c7 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["a_1", "foo_bar", "hello_world"]|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 standalone clean_colnames() on DataFrame\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 standalone clean_colnames() on DataFrame\n    Expected: [\"a_1\", \"foo_bar\", \"hello_world\"]\n    Got: %s\n" result
  end;

  (* Test standalone clean_colnames() on a List *)
  let env_c8 = Eval.initial_env () in
  let (v, _) = eval_string_env {|clean_colnames(["A.1", "A-1"])|} env_c8 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["a_1", "a_1_2"]|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 standalone clean_colnames() on List\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 standalone clean_colnames() on List\n    Expected: [\"a_1\", \"a_1_2\"]\n    Got: %s\n" result
  end;

  (* Test idempotence: clean(clean(x)) == clean(x) *)
  let env_c9 = Eval.initial_env () in
  let (_, env_c9) = eval_string_env (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_symbols) env_c9 in
  let (_, env_c9) = eval_string_env "df2 = clean_colnames(df)" env_c9 in
  let (v1, _) = eval_string_env "colnames(df)" env_c9 in
  let (v2, _) = eval_string_env "colnames(df2)" env_c9 in
  let r1 = Ast.Utils.value_to_string v1 in
  let r2 = Ast.Utils.value_to_string v2 in
  if r1 = r2 then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 clean_colnames is idempotent\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 clean_colnames is idempotent\n    First clean: %s\n    Second clean: %s\n" r1 r2
  end;
  print_newline ();

  (* ================================================================= *)
  (* separator alias tests                                              *)
  (* ================================================================= *)
  Printf.printf "Phase — read_csv() with separator alias:\n";

  let csv_path_sep_alias = "test_sep_alias.csv" in
  let oc_sa = open_out csv_path_sep_alias in
  output_string oc_sa "name|age|score\nAlice|30|95.5\nBob|25|87.3\n";
  close_out oc_sa;

  let env_sa = Eval.initial_env () in
  let (_, env_sa) = eval_string_env (Printf.sprintf {|df = read_csv("%s", separator = "|")|} csv_path_sep_alias) env_sa in
  let (v, _) = eval_string_env "nrow(df)" env_sa in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 read_csv with separator=\"|\" reads correct rows\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 read_csv with separator=\"|\" reads correct rows\n    Expected: 2\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "colnames(df)" env_sa in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 read_csv with separator=\"|\" reads correct columns\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 read_csv with separator=\"|\" reads correct columns\n    Expected: [\"name\", \"age\", \"score\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "df.name" env_sa in
  let result = Ast.Utils.value_to_string v in
  if result = {|Vector["Alice", "Bob"]|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 read_csv with separator=\"|\" reads correct values\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 read_csv with separator=\"|\" reads correct values\n    Expected: Vector[\"Alice\", \"Bob\"]\n    Got: %s\n" result
  end;

  (* Test write_csv with separator alias *)
  let csv_out_sep_alias = "test_write_sep_alias.csv" in
  let env_wsa = Eval.initial_env () in
  let (_, env_wsa) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_path) env_wsa in
  let (v, _) = eval_string_env (Printf.sprintf {|write_csv(df, "%s", separator = ";")|} csv_out_sep_alias) env_wsa in
  let result = Ast.Utils.value_to_string v in
  if result = "null" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 write_csv with separator=\";\" returns null\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 write_csv with separator=\";\" returns null\n    Expected: null\n    Got: %s\n" result
  end;

  (* Roundtrip: read back the semicolon-separated file written with separator alias *)
  let (_, env_wsa2) = eval_string_env (Printf.sprintf {|df2 = read_csv("%s", separator = ";")|} csv_out_sep_alias) env_wsa in
  let (v, _) = eval_string_env "nrow(df2)" env_wsa2 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 roundtrip with separator=\";\" preserves row count\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 roundtrip with separator=\";\" preserves row count\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "colnames(df2)" env_wsa2 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 roundtrip with separator=\";\" preserves column names\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 roundtrip with separator=\";\" preserves column names\n    Expected: [\"name\", \"age\", \"score\"]\n    Got: %s\n" result
  end;

  test "read_csv separator bad type"
    {|read_csv("test_phase2.csv", separator = 42)|}
    {|Error(TypeError: "Function `read_csv` separator must be a single character string.")|};
  test "read_csv separator too long"
    {|read_csv("test_phase2.csv", separator = "||")|}
    {|Error(TypeError: "Function `read_csv` separator must be a single character string.")|};
  print_newline ();

  (* ================================================================= *)
  (* head/tail on DataFrames                                            *)
  (* ================================================================= *)
  Printf.printf "Phase — head() and tail() on DataFrames:\n";

  let csv_path_ht = "test_head_tail.csv" in
  let oc_ht = open_out csv_path_ht in
  output_string oc_ht "x,y\n1,a\n2,b\n3,c\n4,d\n5,e\n6,f\n7,g\n8,h\n";
  close_out oc_ht;

  let env_ht = Eval.initial_env () in
  let (_, env_ht) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_path_ht) env_ht in

  (* head default n=5 *)
  let (v, _) = eval_string_env "nrow(head(df))" env_ht in
  let result = Ast.Utils.value_to_string v in
  if result = "5" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 head(df) returns 5 rows by default\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 head(df) returns 5 rows by default\n    Expected: 5\n    Got: %s\n" result
  end;

  (* head with n=3 as positional arg *)
  let (v, _) = eval_string_env "nrow(head(df, 3))" env_ht in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 head(df, 3) returns 3 rows\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 head(df, 3) returns 3 rows\n    Expected: 3\n    Got: %s\n" result
  end;

  (* head with n=3 as named arg *)
  let (v, _) = eval_string_env "nrow(head(df, n = 3))" env_ht in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 head(df, n=3) returns 3 rows\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 head(df, n=3) returns 3 rows\n    Expected: 3\n    Got: %s\n" result
  end;

  (* head preserves columns *)
  let (v, _) = eval_string_env "h = head(df, 2); h.x" env_ht in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 2]" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 head(df, 2) preserves column data\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 head(df, 2) preserves column data\n    Expected: Vector[1, 2]\n    Got: %s\n" result
  end;

  (* head n > nrow *)
  let (v, _) = eval_string_env "nrow(head(df, 100))" env_ht in
  let result = Ast.Utils.value_to_string v in
  if result = "8" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 head(df, 100) returns all rows when n > nrow\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 head(df, 100) returns all rows when n > nrow\n    Expected: 8\n    Got: %s\n" result
  end;

  (* tail default n=5 *)
  let (v, _) = eval_string_env "nrow(tail(df))" env_ht in
  let result = Ast.Utils.value_to_string v in
  if result = "5" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 tail(df) returns 5 rows by default\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 tail(df) returns 5 rows by default\n    Expected: 5\n    Got: %s\n" result
  end;

  (* tail with n=3 as positional arg *)
  let (v, _) = eval_string_env "nrow(tail(df, 3))" env_ht in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 tail(df, 3) returns 3 rows\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 tail(df, 3) returns 3 rows\n    Expected: 3\n    Got: %s\n" result
  end;

  (* tail with n=3 as named arg *)
  let (v, _) = eval_string_env "nrow(tail(df, n = 3))" env_ht in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 tail(df, n=3) returns 3 rows\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 tail(df, n=3) returns 3 rows\n    Expected: 3\n    Got: %s\n" result
  end;

  (* tail returns last rows *)
  let (v, _) = eval_string_env "t = tail(df, 2); t.x" env_ht in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[7, 8]" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 tail(df, 2) returns last rows\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 tail(df, 2) returns last rows\n    Expected: Vector[7, 8]\n    Got: %s\n" result
  end;

  (* tail n > nrow *)
  let (v, _) = eval_string_env "nrow(tail(df, 100))" env_ht in
  let result = Ast.Utils.value_to_string v in
  if result = "8" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 tail(df, 100) returns all rows when n > nrow\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 tail(df, 100) returns all rows when n > nrow\n    Expected: 8\n    Got: %s\n" result
  end;

  (* head/tail preserve list behavior *)
  test "head on list still works"
    "head([1, 2, 3])"
    "1";
  test "tail on list still works"
    "tail([1, 2, 3])"
    "[2, 3]";
  print_newline ();

  (* ================================================================= *)
  (* glimpse() tests                                                    *)
  (* ================================================================= *)
  Printf.printf "Phase — glimpse():\n";

  let env_gl = Eval.initial_env () in
  let (_, env_gl) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_path) env_gl in

  let (v, _) = eval_string_env "g = glimpse(df)" env_gl in
  let result = Ast.Utils.value_to_string v in
  if result = "null" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 glimpse returns null (prints to stdout)\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 glimpse returns null\n    Expected: null\n    Got: %s\n" result
  end;

  test "glimpse on non-DataFrame"
    "glimpse(42)"
    {|Error(TypeError: "Function `glimpse` expects a DataFrame.")|};
  test "glimpse on NA"
    "glimpse(NA)"
    {|Error(TypeError: "Function `glimpse` expects a DataFrame, got NA.")|};
  print_newline ();

  (* ================================================================= *)
  (* explain() compact display for DataFrames                           *)
  (* ================================================================= *)
  Printf.printf "Phase — explain() compact display for DataFrames:\n";

  let env_ex = Eval.initial_env () in
  let (_, env_ex) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_path) env_ex in

  (* Compact display should not contain schema, na_stats, example_rows *)
  let (v, _) = eval_string_env "explain(df)" env_ex in
  let result = Ast.Utils.value_to_string v in
  let contains_sub s sub =
    let slen = String.length s in
    let sublen = String.length sub in
    if sublen > slen then false
    else
      let found = ref false in
      for i = 0 to slen - sublen do
        if not !found && String.sub s i sublen = sub then found := true
      done;
      !found
  in
  let has_schema = contains_sub result "`schema`:" in
  let has_na_stats = contains_sub result "`na_stats`:" in
  let has_example = contains_sub result "`example_rows`:" in
  if not has_schema && not has_na_stats && not has_example then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 explain(df) display does not show schema/na_stats/example_rows\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 explain(df) display does not show schema/na_stats/example_rows\n    Got: %s\n" result
  end;

  (* But fields should be accessible via dot notation *)
  let (v, _) = eval_string_env "e = explain(df); type(e.schema)" env_ex in
  let result = Ast.Utils.value_to_string v in
  if result = {|"List"|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 explain(df).schema still accessible\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 explain(df).schema still accessible\n    Expected: \"List\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); type(e.na_stats)" env_ex in
  let result = Ast.Utils.value_to_string v in
  if result = {|"Dict"|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 explain(df).na_stats still accessible\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 explain(df).na_stats still accessible\n    Expected: \"Dict\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); type(e.example_rows)" env_ex in
  let result = Ast.Utils.value_to_string v in
  if result = {|"List"|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 explain(df).example_rows still accessible\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 explain(df).example_rows still accessible\n    Expected: \"List\"\n    Got: %s\n" result
  end;

  (* Hint message should be present *)
  let (v, _) = eval_string_env "e = explain(df); type(e.hint)" env_ex in
  let result = Ast.Utils.value_to_string v in
  if result = {|"String"|} then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 explain(df) has hint field\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 explain(df) has hint field\n    Expected: \"String\"\n    Got: %s\n" result
  end;
  print_newline ();

  (* ================================================================= *)
  (* URL read_csv tests                                                 *)
  (* ================================================================= *)
  Printf.printf "Phase — read_csv() from URL with separator:\n";

  let url = "https://raw.githubusercontent.com/b-rodrigues/rixpress_demos/refs/heads/master/r_python_quarto/data/mtcars.csv" in
  (* Note: This test requires internet access *)
  let env_url = Eval.initial_env () in
  let (_, env_url) = eval_string_env (Printf.sprintf {|df = read_csv("%s", separator = "|")|} url) env_url in
  
  let (v, _) = eval_string_env "nrow(df)" env_url in
  let result = Ast.Utils.value_to_string v in
  (* mtcars has 32 rows *)
  if result = "32" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 read_csv from URL with separator=\"|\" reads correct rows (32)\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 read_csv from URL with separator=\"|\" reads correct rows\n    Expected: 32\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "ncol(df)" env_url in
  let result = Ast.Utils.value_to_string v in
  (* mtcars has 11 columns *)
  if result = "11" then begin
    incr pass_count; Printf.printf "  \xe2\x9c\x93 read_csv from URL with separator=\"|\" reads correct columns (11)\n"
  end else begin
    incr fail_count; Printf.printf "  \xe2\x9c\x97 read_csv from URL with separator=\"|\" reads correct columns\n    Expected: 11\n    Got: %s\n" result
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
  (try Sys.remove csv_out_sep with _ -> ());
  (try Sys.remove csv_path_symbols with _ -> ());
  (try Sys.remove csv_path_punct with _ -> ());
  (try Sys.remove csv_path_unicode with _ -> ());
  (try Sys.remove csv_path_collide with _ -> ());
  (try Sys.remove csv_path_digits with _ -> ());
  (try Sys.remove csv_path_sep_alias with _ -> ());
  (try Sys.remove csv_out_sep_alias with _ -> ());
  (try Sys.remove csv_path_ht with _ -> ())
