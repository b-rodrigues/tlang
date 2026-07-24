let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Testcraft — expect_ds coverage:\n";

  (* expect_no_na: scalar/vector/list/dataframe *)
  test "expect_no_na int"           "expect_no_na(42)" "PASS";
  test "expect_no_na string"        "expect_no_na(\"hello\")" "PASS";
  test "expect_no_na vector pass"   "expect_no_na([1, 2, 3])" "PASS";
  test "expect_no_na list stop"     "expect_no_na([1, NA, 3])" "STOP(List contains NA values)";
  test "expect_no_na list pass"     "expect_no_na([a: 1, b: 2])" "PASS";
  test "expect_no_na df pass"
    "df = to_dataframe([x: [1, 2], y: [3, 4]]); expect_no_na(df)" "PASS";
  test "expect_no_na df col pass"
    "df = to_dataframe([x: [1, 2], y: [3, 4]]); expect_no_na(df, \"x\")" "PASS";
  test "expect_no_na NA"            "expect_no_na(NA)" "STOP(Value is NA)";
  test "expect_no_na Error"         "expect_no_na(error(\"boom\"))" "STOP(`actual` is an error: boom";

  (* expect_between: scalar/vector *)
  test "expect_between pass"      "expect_between(5, 1, 10)" "PASS";
  test "expect_between min pass"  "expect_between(1, 1, 10)" "PASS";
  test "expect_between max pass"  "expect_between(10, 1, 10)" "PASS";
  test "expect_between stop low"  "expect_between(0, 1, 10)" "STOP(";
  test "expect_between stop high" "expect_between(11, 1, 10)" "STOP(";
  test "expect_between float"     "expect_between(5.5, 1.0, 10.0)" "PASS";
  test "expect_between NA"        "expect_between(NA, 1, 10)" "HOLD(";
  test "expect_between Error"     "expect_between(error(\"boom\"), 1, 10)" "STOP(`actual` is an error: boom";
  test "expect_between string"    "expect_between(\"a\", 1, 10)" "expects a numeric value";

  (* expect_match: regex *)
  test "expect_match pass"      "expect_match(\"hello world\", \"hello\")" "PASS";
  test "expect_match pass re"   "expect_match(\"hello123\", \"[0-9]+\")" "PASS";
  test "expect_match stop"      "expect_match(\"hello\", \"[0-9]+\")" "STOP(";
  test "expect_match NA"        "expect_match(NA, \"hello\")" "HOLD(";
  test "expect_match Error"     "expect_match(error(\"boom\"), \"hello\")" "STOP(`actual` is an error: boom";
  test "expect_match bad re"    "expect_match(\"hello\", \"[\")" "STOP(Invalid regex";

  (* expect_str_contains: substring *)
  test "expect_str_contains pass"      "expect_str_contains(\"hello world\", \"world\")" "PASS";
  test "expect_str_contains stop"      "expect_str_contains(\"hello\", \"xyz\")" "STOP(";
  test "expect_str_contains NA"        "expect_str_contains(NA, \"x\")" "HOLD(";
  test "expect_str_contains Error"     "expect_str_contains(error(\"boom\"), \"x\")" "STOP(`actual` is an error: boom";

  (* expect_set_equal: order-independent *)
  test "expect_set_equal pass"         "expect_set_equal([3, 1, 2], [1, 2, 3])" "PASS";
  test "expect_set_equal stop missing" "expect_set_equal([1, 2], [1, 2, 3])" "STOP(";
  test "expect_set_equal stop extra"   "expect_set_equal([1, 2, 3, 4], [1, 2, 3])" "STOP(";
  test "expect_set_equal NA"           "expect_set_equal(NA, [1, 2])" "HOLD(";
  test "expect_set_equal Error"        "expect_set_equal(error(\"boom\"), [1, 2])" "STOP(`actual` is an error: boom";
  test "expect_set_equal type error"   "expect_set_equal(42, [1, 2])" "expects a List or Vector";

  (* expect_empty: containers *)
  test "expect_empty list"       "expect_empty([])" "PASS";
  test "expect_empty vector"     "expect_empty([])" "PASS";
  test "expect_empty string"     "expect_empty(\"\")" "PASS";
  test "expect_empty df pass"
    "df = to_dataframe([x: []]); expect_empty(df)" "PASS";
  test "expect_empty list stop"  "expect_empty([1, 2])" "STOP(";
  test "expect_empty string stop" "expect_empty(\"hi\")" "STOP(";
  test "expect_empty NA"         "expect_empty(NA)" "HOLD(";
  test "expect_empty Error"      "expect_empty(error(\"boom\"))" "STOP(`actual` is an error: boom";

  (* expect_summary: dict/list of expects *)
  test "expect_summary dict pass"
    "d = [a: expect_equal(1, 1), b: expect_equal(2, 2)]; s = expect_summary(d); nrow(s)" "2";
  test "expect_summary dict has fail"
    "d = [a: expect_equal(1, 1), b: expect_equal(1, 2)]; s = expect_summary(d); nrow(s)" "2";
  test "expect_summary NA"       "expect_summary(NA)" "expects a Dict or List";

  (* expect_column_types: type checking *)
  test "expect_column_types pass"
    "df = to_dataframe([x: [1, 2], y: [\"a\", \"b\"]]); expect_column_types(df, [x: \"Int\", y: \"String\"])" "PASS";
  test "expect_column_types stop"
    "df = to_dataframe([x: [1, 2]]); expect_column_types(df, [x: \"Float\"])" "STOP(";
  test "expect_column_types invalid type spec"
    "df = to_dataframe([x: [1, 2]]); expect_column_types(df, [x: 123])" "expects column types as String or Symbol";
  test "expect_column_types missing col"
    "df = to_dataframe([x: [1, 2]]); expect_column_types(df, [y: \"Int\"])" "STOP(";
  test "expect_column_types NA"  "expect_column_types(NA, [x: \"Int\"])" "HOLD(";
  test "expect_column_types Error" "expect_column_types(error(\"boom\"), [x: \"Int\"])" "STOP(`actual` is an error: boom";

  (* expect_values: allowed set checking *)
  test "expect_values pass"
    "df = to_dataframe([x: [1, 2, 1]]); expect_values(df, \"x\", [1, 2])" "PASS";
  test "expect_values stop"
    "df = to_dataframe([x: [1, 2, 3]]); expect_values(df, \"x\", [1, 2])" "STOP(";
  test "expect_values datetime pass"
    "dt = parse_datetime(\"2023-01-01T10:00:00Z\"); df = to_dataframe([ts: [dt]]); expect_values(df, \"ts\", [dt])" "PASS";
  test "expect_values NA"
    "expect_values(NA, \"x\", [1, 2])" "HOLD(";
  test "expect_values Error"
    "expect_values(error(\"boom\"), \"x\", [1, 2])" "STOP(`actual` is an error: boom";
  test "expect_values col not found"
    "df = to_dataframe([x: [1, 2]]); expect_values(df, \"y\", [1, 2])" "STOP(";

  (* expect_range: column value bounds *)
  test "expect_range pass"
    "df = to_dataframe([x: [1, 5, 10]]); expect_range(df, \"x\", 1, 10)" "PASS";
  test "expect_range stop"
    "df = to_dataframe([x: [1, 5, 15]]); expect_range(df, \"x\", 1, 10)" "STOP(";
  test "expect_range int col"
    "df = to_dataframe([x: [1, 5, 10]]); expect_range(df, \"x\", 1, 10)" "PASS";
  test "expect_range NA"
    "expect_range(NA, \"x\", 1, 10)" "HOLD(";
  test "expect_range Error"
    "expect_range(error(\"boom\"), \"x\", 1, 10)" "STOP(`actual` is an error: boom";
  test "expect_range col not found"
    "df = to_dataframe([x: [1, 2]]); expect_range(df, \"y\", 1, 10)" "STOP(";

  (* expect_table_equal: DataFrame equality *)
  test "expect_table_equal pass"
    "df1 = to_dataframe([x: [1, 2], y: [3, 4]]); df2 = to_dataframe([x: [1, 2], y: [3, 4]]); expect_table_equal(df1, df2)" "PASS";
  test "expect_table_equal row mismatch"
    "df1 = to_dataframe([x: [1, 2]]); df2 = to_dataframe([x: [1, 2, 3]]); expect_table_equal(df1, df2)" "STOP(Row count mismatch";
  test "expect_table_equal col mismatch"
    "df1 = to_dataframe([x: [1]]); df2 = to_dataframe([y: [1]]); expect_table_equal(df1, df2)" "STOP(Column names mismatch";
  test "expect_table_equal ignore order"
    "df1 = to_dataframe([x: [1, 2, 3]]); df2 = to_dataframe([x: [3, 1, 2]]); expect_table_equal(df1, df2, true)" "PASS";
  test "expect_table_equal no ignore order"
    "df1 = to_dataframe([x: [1, 2, 3]]); df2 = to_dataframe([x: [3, 1, 2]]); expect_table_equal(df1, df2, false)" "STOP(";
  test "expect_table_equal actual NA"
    "expect_table_equal(NA, to_dataframe([x: [1]]))" "HOLD(`actual` is NA";
  test "expect_table_equal expected NA"
    "expect_table_equal(to_dataframe([x: [1]]), NA)" "HOLD(`expected` is NA";
  test "expect_table_equal actual Error"
    "expect_table_equal(error(\"boom\"), to_dataframe([x: [1]]))" "STOP(`actual` is an error: boom";
  test "expect_table_equal expected Error"
    "expect_table_equal(to_dataframe([x: [1]]), error(\"boom\"))" "STOP(`expected` is an error: boom";
