let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Testcraft — relational, type, ds:\n";

  (* Relational *)
  test "expect_lt pass"    "expect_lt(1, 2)" "PASS";
  test "expect_lt stop"    "expect_lt(2, 1)" "STOP(";
  test "expect_lt equal"   "expect_lt(1, 1)" "STOP(`1`";
  test "expect_lte pass"   "expect_lte(1, 2)" "PASS";
  test "expect_lte equal"  "expect_lte(1, 1)" "PASS";
  test "expect_lte stop"   "expect_lte(2, 1)" "STOP(";
  test "expect_gt pass"    "expect_gt(2, 1)" "PASS";
  test "expect_gt stop"    "expect_gt(1, 2)" "STOP(";
  test "expect_gte pass"   "expect_gte(2, 1)" "PASS";
  test "expect_gte equal"  "expect_gte(1, 1)" "PASS";
  test "expect_gte stop"   "expect_gte(1, 2)" "STOP(";
  test "expect_lt float"   "expect_lt(1.5, 2.5)" "PASS";
  test "expect_lt cross"   "expect_lt(1, 2.5)" "PASS";
  test "expect_lt string"  {|expect_lt("a", "b")|} "STOP(";

  (* Truth *)
  test "expect_true pass"    "expect_true(true)" "PASS";
  test "expect_true stop"    "expect_true(false)" "STOP(";
  test "expect_true not bool" "expect_true(1)" "STOP(";
  test "expect_false pass"   "expect_false(false)" "PASS";
  test "expect_false stop"   "expect_false(true)" "STOP(";
  test "expect_truthy"       "expect_truthy(42)" "PASS";
  test "expect_truthy zero"  "expect_truthy(0)" "STOP(";
  test "expect_falsy zero"   "expect_falsy(0)" "PASS";
  test "expect_falsy 42"     "expect_falsy(42)" "STOP(";

  (* Type *)
  test "expect_type pass"    {|expect_type(1, "Int")|} "PASS";
  test "expect_type stop"    {|expect_type(1, "Float")|} "STOP(";
  test "expect_type string"  {|expect_type("hello", "String")|} "PASS";

  (* Error *)
  test "expect_error pass"   {|expect_error(error("boom"))|} "PASS";
  test "expect_error stop"   {|expect_error(42)|} "STOP(";
  test "expect_error class pass"
    {|expect_error(error("boom"), class = "GenericError")|} "PASS";
  test "expect_error class stop"
    {|expect_error(error("boom"), class = "TypeError")|} "STOP(";
  test "expect_error message pass"
    {|expect_error(error("invalid value"), message = "invalid")|} "PASS";
  test "expect_error message stop"
    {|expect_error(error("invalid value"), message = "boom")|} "STOP(";

  (* Length -- avoid reserved name `n`, use `x` *)
  test "expect_length vector"  "x = [1, 2, 3, 4, 5]; expect_length(x, 5)" "PASS";
  test "expect_length vector stop" "x = [1, 2, 3]; expect_length(x, 5)" "STOP(";
  test "expect_length string"  {|expect_length("hello", 5)|} "PASS";
  test "expect_length string stop" {|expect_length("hi", 3)|} "STOP(";

  (* Data frame -- use to_dataframe instead of read_csv *)
  test "expect_nrow pass"
    "df = to_dataframe([x: [1, 3, 5], y: [2, 4, 6]]); expect_nrow(df, 3)" "PASS";
  test "expect_nrow stop"
    "df = to_dataframe([x: [1, 3, 5], y: [2, 4, 6]]); expect_nrow(df, 5)" "STOP(";
  test "expect_ncol pass"
    "df = to_dataframe([x: [1, 3], y: [2, 4]]); expect_ncol(df, 2)" "PASS";
  test "expect_ncol stop"
    "df = to_dataframe([x: [1], y: [2]]); expect_ncol(df, 5)" "STOP(";
  test "expect_colnames pass"
    "df = to_dataframe([x: [1], y: [2]]); expect_colnames(df, [\"x\", \"y\"])" "PASS";
  test "expect_colnames stop"
    "df = to_dataframe([x: [1], y: [2]]); expect_colnames(df, [\"x\"])" "STOP(";

  (* Fields *)
  test "expect_fields dict pass"
    {|d = [a: 1, b: 2]; expect_fields(d, ["a", "b"])|} "PASS";
  test "expect_fields dict stop"
    {|d = [a: 1, b: 2]; expect_fields(d, ["c", "d"])|} "STOP(";

  (* Membership *)
  test "expect_in scalar pass"
    "v = [1, 2, 3, 4, 5]; expect_in(3, v)" "PASS";
  test "expect_in scalar stop"
    "v = [1, 2, 3]; expect_in(10, v)" "STOP(";

  Printf.printf "\n"
