
let run_tests pass_count fail_count _failures _eval_string eval_string_env test test_env =
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
  let env = Packages.init_env () in
  let env = Test_helpers.eval_setup eval_string_env env "test_dataframe:27" (Printf.sprintf {|df = read_csv("%s")|} csv_path) in
  test_env env "read_csv returns DataFrame"
    "type(df)" {|"DataFrame"|};

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
  test_env env "nrow returns correct count"
    "nrow(df)" "3";
  test_env env "ncol returns correct count"
    "ncol(df)" "3";

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
  test_env env "colnames returns column names"
    "colnames(df)" {|["name", "age", "score"]|};

  test "colnames on non-DataFrame"
    {|colnames("hello")|}
    {|Error(TypeError: "Function `colnames` expects a DataFrame.")|};
  print_newline ();

  Printf.printf "Phase 2 — Column Access (dot notation):\n";
  test_env env "column access by name returns Vector"
    "df.name" {|Vector["Alice", "Bob", "Charlie"]|};
  test_env env "numeric column access returns typed values"
    "df.age" "Vector[30, 25, 35]";
  test_env env "float column access returns typed values"
    "df.score" "Vector[95.5, 87.3, 92.1]";
  test_env env "missing column returns error"
    "df.nonexistent" {|Error(KeyError: "Column `nonexistent` not found in DataFrame.")|};
  print_newline ();

  Printf.printf "Phase 2 — DataFrame Type Inference:\n";
  let env2 = Test_helpers.eval_setup eval_string_env env "test_dataframe:80" (Printf.sprintf {|df2 = read_csv("%s")|} csv_path_types) in
  test_env env2 "integer columns inferred correctly"
    "df2.id" "Vector[1, 2, 3]";
  test_env env2 "boolean columns inferred correctly"
    "df2.active" "Vector[true, false, true]";
  test_env env2 "float columns inferred correctly"
    "df2.value" "Vector[3.14, 2.71, 1.41]";
  print_newline ();

  Printf.printf "Phase 2 — NA in CSV:\n";
  let env3 = Test_helpers.eval_setup eval_string_env env "test_dataframe:90" (Printf.sprintf {|df3 = read_csv("%s")|} csv_path_na) in
  test_env env3 "NA values preserved in CSV import"
    "df3.x" "Vector[1, NA(Int), 3]";
  print_newline ();

  Printf.printf "Phase 2 — Empty DataFrame:\n";
  let env4 = Test_helpers.eval_setup eval_string_env env "test_dataframe:96" (Printf.sprintf {|df4 = read_csv("%s")|} csv_path_empty) in
  test_env env4 "empty CSV has 0 rows"
    "nrow(df4)" "0";
  test_env env4 "empty CSV retains column count"
    "ncol(df4)" "3";
  print_newline ();

  Printf.printf "Phase 2 — DataFrame in Pipelines:\n";
  test "DataFrame works as pipeline input (nrow)"
    (Printf.sprintf {|read_csv("%s") |> nrow|} csv_path)
    "3";
  test "DataFrame works as pipeline input (colnames)"
    (Printf.sprintf {|read_csv("%s") |> colnames|} csv_path)
    {|["name", "age", "score"]|};
  test "DataFrame works as pipeline input (ncol)"
    (Printf.sprintf {|read_csv("%s") |> ncol|} csv_path)
    "3";
  print_newline ();

  Printf.printf "Phase 2 — DataFrame Display:\n";
  test_env env "DataFrame display format correct"
    "df" "DataFrame(3 rows x 3 cols: [name, age, score])";
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
  let env5 = Packages.init_env () in
  let env5 = Test_helpers.eval_setup eval_string_env env5 "test_dataframe:146" (Printf.sprintf {|df = read_csv("%s", separator = ";")|} csv_path_sep) in
  test_env env5 "read_csv with separator=\";\" reads correct rows"
    "nrow(df)" "2";
  test_env env5 "read_csv with separator=\";\" reads correct columns"
    "colnames(df)" {|["name", "age", "score"]|};

  (* Test read_csv with skip_lines *)
  let env6 = Packages.init_env () in
  let env6 = Test_helpers.eval_setup eval_string_env env6 "test_dataframe:154" (Printf.sprintf {|df = read_csv("%s", skip_lines = 2)|} csv_path_skip) in
  test_env env6 "read_csv with skip_lines=2 skips comment lines"
    "nrow(df)" "2";
  test_env env6 "read_csv with skip_lines=2 reads correct header"
    "colnames(df)" {|["name", "age", "score"]|};

  (* Test read_csv with skip_header *)
  let env7 = Packages.init_env () in
  let env7 = Test_helpers.eval_setup eval_string_env env7 "test_dataframe:162" (Printf.sprintf {|df = read_csv("%s", skip_header = true)|} csv_path_noheader) in
  test_env env7 "read_csv with skip_header=true reads all lines as data"
    "nrow(df)" "2";
  test_env env7 "read_csv with skip_header=true generates V1,V2,V3 column names"
    "colnames(df)" {|["V1", "V2", "V3"]|};
  print_newline ();

  (* Phase 5 — write_csv() with optional arguments *)
  Printf.printf "Phase 5 — write_csv() optional arguments:\n";

  let csv_out_sep = "test_phase5_write_sep.csv" in
  let env_w = Packages.init_env () in
  let env_w = Test_helpers.eval_setup eval_string_env env_w "test_dataframe:174" (Printf.sprintf {|df = read_csv("%s")|} csv_path) in
  test_env env_w "write_csv with separator=\";\" returns NA"
    (Printf.sprintf {|write_csv(df, "%s", separator = ";")|} csv_out_sep) "NA";

  (* Roundtrip: read back the semicolon-separated file *)
  let env_w2 = Test_helpers.eval_setup eval_string_env env_w "test_dataframe:179" (Printf.sprintf {|df2 = read_csv("%s", separator = ";")|} csv_out_sep) in
  test_env env_w2 "roundtrip with separator=\";\" preserves row count"
    "nrow(df2)" "3";
  test_env env_w2 "roundtrip with separator=\";\" preserves column names"
    "colnames(df2)" {|["name", "age", "score"]|};
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

  let env_c1 = Packages.init_env () in
  let env_c1 = Test_helpers.eval_setup eval_string_env env_c1 "test_dataframe:198" (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_symbols) in
  test_env env_c1 "clean_colnames expands symbols"
    "colnames(df)" {|["growth_percent", "million_euro", "price_dollar"]|};

  (* Test CSV with punctuation in column names *)
  let csv_path_punct = "test_clean_punct.csv" in
  let oc_p = open_out csv_path_punct in
  output_string oc_p "A.1,foo---bar,hello world\n1,2,3\n";
  close_out oc_p;

  let env_c2 = Packages.init_env () in
  let env_c2 = Test_helpers.eval_setup eval_string_env env_c2 "test_dataframe:209" (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_punct) in
  test_env env_c2 "clean_colnames handles punctuation"
    "colnames(df)" {|["a_1", "foo_bar", "hello_world"]|};

  (* Test CSV with Unicode diacritics *)
  let csv_path_unicode = "test_clean_unicode.csv" in
  let oc_u = open_out csv_path_unicode in
  output_string oc_u "caf\xc3\xa9,na\xc3\xafve\n1,2\n";
  close_out oc_u;

  let env_c3 = Packages.init_env () in
  let env_c3 = Test_helpers.eval_setup eval_string_env env_c3 "test_dataframe:220" (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_unicode) in
  test_env env_c3 "clean_colnames strips diacritics"
    "colnames(df)" {|["cafe", "naive"]|};

  (* Test collision resolution *)
  let csv_path_collide = "test_clean_collide.csv" in
  let oc_co = open_out csv_path_collide in
  output_string oc_co "A.1,A-1,A_1\n1,2,3\n";
  close_out oc_co;

  let env_c4 = Packages.init_env () in
  let env_c4 = Test_helpers.eval_setup eval_string_env env_c4 "test_dataframe:231" (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_collide) in
  test_env env_c4 "clean_colnames resolves collisions"
    "colnames(df)" {|["a_1", "a_1_2", "a_1_3"]|};

  (* Test digit-prefixed names *)
  let csv_path_digits = "test_clean_digits.csv" in
  let oc_d = open_out csv_path_digits in
  output_string oc_d "1st,2nd_col,normal\n1,2,3\n";
  close_out oc_d;

  let env_c5 = Packages.init_env () in
  let env_c5 = Test_helpers.eval_setup eval_string_env env_c5 "test_dataframe:242" (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_digits) in
  test_env env_c5 "clean_colnames prefixes digit-leading names"
    "colnames(df)" {|["x_1st", "x_2nd_col", "normal"]|};

  (* Test clean_colnames = false preserves original names *)
  let env_c6 = Packages.init_env () in
  let env_c6 = Test_helpers.eval_setup eval_string_env env_c6 "test_dataframe:248" (Printf.sprintf {|df = read_csv("%s", clean_colnames = false)|} csv_path_punct) in
  test_env env_c6 "clean_colnames = false preserves original names"
    "colnames(df)" {|["A.1", "foo---bar", "hello world"]|};

  (* Test standalone clean_colnames() on a DataFrame *)
  let env_c7 = Packages.init_env () in
  let env_c7 = Test_helpers.eval_setup eval_string_env env_c7 "test_dataframe:254" (Printf.sprintf {|df = read_csv("%s")|} csv_path_punct) in
  let env_c7 = Test_helpers.eval_setup eval_string_env env_c7 "test_dataframe:255" "df2 = clean_colnames(df)" in
  test_env env_c7 "standalone clean_colnames() on DataFrame"
    "colnames(df2)" {|["a_1", "foo_bar", "hello_world"]|};

  (* Test standalone clean_colnames() on a List *)
  test "standalone clean_colnames() on List"
    {|clean_colnames(["A.1", "A-1"])|}
    {|["a_1", "a_1_2"]|};

  (* Test idempotence: clean(clean(x)) == clean(x) *)
  let env_c9 = Packages.init_env () in
  let env_c9 = Test_helpers.eval_setup eval_string_env env_c9 "test_dataframe:266" (Printf.sprintf {|df = read_csv("%s", clean_colnames = true)|} csv_path_symbols) in
  let env_c9 = Test_helpers.eval_setup eval_string_env env_c9 "test_dataframe:267" "df2 = clean_colnames(df)" in
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

  let env_sa = Packages.init_env () in
  let env_sa = Test_helpers.eval_setup eval_string_env env_sa "test_dataframe:290" (Printf.sprintf {|df = read_csv("%s", separator = "|")|} csv_path_sep_alias) in
  test_env env_sa "read_csv with separator=\"|\" reads correct rows"
    "nrow(df)" "2";
  test_env env_sa "read_csv with separator=\"|\" reads correct columns"
    "colnames(df)" {|["name", "age", "score"]|};
  test_env env_sa "read_csv with separator=\"|\" reads correct values"
    "df.name" {|Vector["Alice", "Bob"]|};

  (* Test write_csv with separator alias *)
  let csv_out_sep_alias = "test_write_sep_alias.csv" in
  let env_wsa = Packages.init_env () in
  let env_wsa = Test_helpers.eval_setup eval_string_env env_wsa "test_dataframe:301" (Printf.sprintf {|df = read_csv("%s")|} csv_path) in
  test_env env_wsa "write_csv with separator=\";\" returns NA"
    (Printf.sprintf {|write_csv(df, "%s", separator = ";")|} csv_out_sep_alias) "NA";

  (* Roundtrip: read back the semicolon-separated file written with separator alias *)
  let env_wsa2 = Test_helpers.eval_setup eval_string_env env_wsa "test_dataframe:306" (Printf.sprintf {|df2 = read_csv("%s", separator = ";")|} csv_out_sep_alias) in
  test_env env_wsa2 "roundtrip with separator=\";\" preserves row count"
    "nrow(df2)" "3";
  test_env env_wsa2 "roundtrip with separator=\";\" preserves column names"
    "colnames(df2)" {|["name", "age", "score"]|};

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

  let env_ht = Packages.init_env () in
  let env_ht = Test_helpers.eval_setup eval_string_env env_ht "test_dataframe:331" (Printf.sprintf {|df = read_csv("%s")|} csv_path_ht) in

  test_env env_ht "head(df) returns 5 rows by default"
    "nrow(head(df))" "5";
  test_env env_ht "head(df, 3) returns 3 rows"
    "nrow(head(df, 3))" "3";
  test_env env_ht "head(df, n=3) returns 3 rows"
    "nrow(head(df, n = 3))" "3";
  test_env env_ht "head(df, 2) preserves column data"
    "h = head(df, 2); h.x" "Vector[1, 2]";
  test_env env_ht "head(df, 100) returns all rows when n > nrow"
    "nrow(head(df, 100))" "8";
  test_env env_ht "tail(df) returns 5 rows by default"
    "nrow(tail(df))" "5";
  test_env env_ht "tail(df, 3) returns 3 rows"
    "nrow(tail(df, 3))" "3";
  test_env env_ht "tail(df, n=3) returns 3 rows"
    "nrow(tail(df, n = 3))" "3";
  test_env env_ht "tail(df, 2) returns last rows"
    "t = tail(df, 2); t.x" "Vector[7, 8]";
  test_env env_ht "tail(df, 100) returns all rows when n > nrow"
    "nrow(tail(df, 100))" "8";

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

  let env_gl = Packages.init_env () in
  let env_gl = Test_helpers.eval_setup eval_string_env env_gl "test_dataframe:369" (Printf.sprintf {|df = read_csv("%s")|} csv_path) in

  test_env env_gl "glimpse returns NA (prints to stdout)"
    "g = glimpse(df)" "NA";

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

  let env_ex = Packages.init_env () in
  let env_ex = Test_helpers.eval_setup eval_string_env env_ex "test_dataframe:388" (Printf.sprintf {|df = read_csv("%s")|} csv_path) in

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
  test_env env_ex "explain(df).schema still accessible"
    "e = explain(df); type(e.schema)" {|"List"|};
  test_env env_ex "explain(df).na_stats still accessible"
    "e = explain(df); type(e.na_stats)" {|"Dict"|};
  test_env env_ex "explain(df).example_rows still accessible"
    "e = explain(df); type(e.example_rows)" {|"List"|};
  test_env env_ex "explain(df) has hint field"
    "e = explain(df); type(e.hint)" {|"String"|};
  print_newline ();

  (* ================================================================= *)
  (* URL read_csv tests                                                 *)
  (* ================================================================= *)
  Printf.printf "Phase — read_csv() from URL with separator:\n";

  let url = "https://raw.githubusercontent.com/b-rodrigues/rixpress_demos/refs/heads/master/r_python_quarto/data/mtcars.csv" in
  (* Note: This test requires internet access. eval_setup is fail-fast, so a
     VError here (e.g. no network) would raise Failure and abort the whole
     test binary. Catch it and skip just the URL-dependent assertions instead. *)
  let env_url =
    try
      Some (Test_helpers.eval_setup eval_string_env (Packages.init_env ()) "test_dataframe:432" (Printf.sprintf {|df = read_csv("%s", separator = "|")|} url))
    with Failure _ ->
      Printf.printf "  - [setup:test_dataframe:432] read_csv from URL unavailable (offline?) — skipping URL tests\n";
      None
  in
  (match env_url with
  | Some env_url ->
    test_env env_url "read_csv from URL with separator=\"|\" reads correct rows (32)"
      "nrow(df)" "32";
    test_env env_url "read_csv from URL with separator=\"|\" reads correct columns (11)"
      "ncol(df)" "11";
  | None -> ());
  Printf.printf "Phase — to_array():\n";
  test "to_array with list of symbols"
    "df_arr = to_dataframe([[a: 1, b: 2], [a: 3, b: 4]]); to_array(df_arr, [$a, $b]) |> type"
    {|"NDArray"|};
  
  test "to_array with vector of symbols"
    "df_arr = to_dataframe([[a: 1, b: 2], [a: 3, b: 4]]); to_array(df_arr, [$a]) |> type"
    {|"NDArray"|};
    
  test "to_array single column symbol"
    "df_arr = to_dataframe([[a: 1, b: 2], [a: 3, b: 4]]); to_array(df_arr, $a) |> type"
    {|"NDArray"|};

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
