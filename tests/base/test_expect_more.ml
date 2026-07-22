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

  (* Relational NA / Error *)
  test "expect_lt actual NA"   "expect_lt(NA, 1)" "HOLD(";
  test "expect_lt expected NA" "expect_lt(1, NA)" "HOLD(";
  test "expect_lt actual Error"   "expect_lt(error(\"boom\"), 1)" "STOP(`actual` is an error: boom";
  test "expect_lt expected Error" "expect_lt(1, error(\"boom\"))" "STOP(`expected` is an error: boom";

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

  (* Truth NA / Error *)
  test "expect_true NA"      "expect_true(NA)" "HOLD(";
  test "expect_true Error"   "expect_true(error(\"boom\"))" "STOP(`actual` is an error: boom";
  test "expect_false NA"     "expect_false(NA)" "HOLD(";
  test "expect_false Error"  "expect_false(error(\"boom\"))" "STOP(`actual` is an error: boom";
  test "expect_truthy NA"    "expect_truthy(NA)" "HOLD(";
  test "expect_truthy Error" "expect_truthy(error(\"boom\"))" "STOP(`actual` is an error: boom";
  test "expect_falsy NA"     "expect_falsy(NA)" "HOLD(";
  test "expect_falsy Error"  "expect_falsy(error(\"boom\"))" "STOP(`actual` is an error: boom";

  (* Type *)
  test "expect_type pass"    {|expect_type(1, "Int")|} "PASS";
  test "expect_type stop"    {|expect_type(1, "Float")|} "STOP(";
  test "expect_type string"  {|expect_type("hello", "String")|} "PASS";
  test "expect_type NA"      "expect_type(NA, \"Int\")" "HOLD(";
  test "expect_type Error"   "expect_type(error(\"boom\"), \"Int\")" "STOP(`actual` is an error: boom";

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
  test "expect_error NA"     "expect_error(NA)" "HOLD(";

  (* Length -- avoid reserved name `n`, use `x` *)
  test "expect_length vector"  "x = [1, 2, 3, 4, 5]; expect_length(x, 5)" "PASS";
  test "expect_length vector stop" "x = [1, 2, 3]; expect_length(x, 5)" "STOP(";
  test "expect_length string"  {|expect_length("hello", 5)|} "PASS";
  test "expect_length string stop" {|expect_length("hi", 3)|} "STOP(";
  test "expect_length NA"      "expect_length(NA, 5)" "HOLD(";
  test "expect_length Error"   "expect_length(error(\"boom\"), 5)" "STOP(`actual` is an error: boom";

  (* Data frame -- use to_dataframe instead of read_csv *)
  test "expect_nrow pass"
    "df = to_dataframe([x: [1, 3, 5], y: [2, 4, 6]]); expect_nrow(df, 3)" "PASS";
  test "expect_nrow stop"
    "df = to_dataframe([x: [1, 3, 5], y: [2, 4, 6]]); expect_nrow(df, 5)" "STOP(";
  test "expect_nrow NA"
    "expect_nrow(NA, 3)" "HOLD(";
  test "expect_nrow Error"
    "expect_nrow(error(\"boom\"), 3)" "STOP(`actual` is an error: boom";

  test "expect_ncol pass"
    "df = to_dataframe([x: [1, 3], y: [2, 4]]); expect_ncol(df, 2)" "PASS";
  test "expect_ncol stop"
    "df = to_dataframe([x: [1], y: [2]]); expect_ncol(df, 5)" "STOP(";
  test "expect_ncol NA"
    "expect_ncol(NA, 2)" "HOLD(";
  test "expect_ncol Error"
    "expect_ncol(error(\"boom\"), 2)" "STOP(`actual` is an error: boom";

  test "expect_colnames pass"
    "df = to_dataframe([x: [1], y: [2]]); expect_colnames(df, [\"x\", \"y\"])" "PASS";
  test "expect_colnames stop"
    "df = to_dataframe([x: [1], y: [2]]); expect_colnames(df, [\"x\"])" "STOP(";
  test "expect_colnames NA"
    "expect_colnames(NA, [\"x\"])" "HOLD(";
  test "expect_colnames Error"
    "expect_colnames(error(\"boom\"), [\"x\"])" "STOP(`actual` is an error: boom";

  (* Fields *)
  test "expect_fields dict pass"
    {|d = [a: 1, b: 2]; expect_fields(d, ["a", "b"])|} "PASS";
  test "expect_fields dict stop"
    {|d = [a: 1, b: 2]; expect_fields(d, ["c", "d"])|} "STOP(";
  test "expect_fields NA"
    "expect_fields(NA, [\"a\"])" "HOLD(";
  test "expect_fields Error"
    "expect_fields(error(\"boom\"), [\"a\"])" "STOP(`actual` is an error: boom";

  (* Membership *)
  test "expect_in scalar pass"
    "v = [1, 2, 3, 4, 5]; expect_in(3, v)" "PASS";
  test "expect_in scalar stop"
    "v = [1, 2, 3]; expect_in(10, v)" "STOP(";
  test "expect_in NA"
    "expect_in(NA, [1, 2])" "HOLD(";
  test "expect_in Error"
    "expect_in(error(\"boom\"), [1, 2])" "STOP(`actual` is an error: boom";
  test "expect_in float pass"
    "expect_in(0.1 + 0.2, [0.3])" "PASS";
  test "expect_in float pass tolerance"
    "expect_in(0.1 + 0.2, [0.3], tolerance = 1e-9)" "PASS";
  test "expect_in float stop tolerance"
    "expect_in(0.1 + 0.2, [0.3], tolerance = 0.0)" "STOP(";
  test "expect_in second arg type error"
    "expect_in(1, 2)" "expects a Vector or List as second argument";
  test "expect_equal lambda"
    "expect_equal(\\(x) x, \\(x) x)" "STOP(Cannot compare functional values";
  test "expect_equal builtin"
    "expect_equal(map, map)" "STOP(Cannot compare functional values";

  (* Dict recursive comparison *)
  test "expect_equal dict pass (order-insensitive)"
    "expect_equal([a: 1, b: 2], [b: 2, a: 1])" "PASS";
  test "expect_equal dict value diff"
    "expect_equal([a: 1, b: 2], [a: 1, b: 3])" "STOP(Dict: key `b` value differs";
  test "expect_equal dict key mismatch"
    "expect_equal([a: 1, b: 2], [a: 1, c: 2])" "STOP(Dict: keys differ: expected `b`, got `c`";
  test "expect_equal dict nested lambda crash-safety"
    "expect_equal([a: \\(x) x], [a: \\(x) x])" "STOP(Dict: key `a` value differs: Cannot compare functional values";
  test "expect_equal dict nested pass"
    "expect_equal([a: [x: 1]], [a: [x: 1]])" "PASS";
  test "expect_equal dict nested mismatch"
    "expect_equal([a: [x: 1]], [a: [x: 2]])" "STOP(Dict: key `a` value differs: Dict: key `x` value differs";
  test "expect_equal dict size mismatch"
    "expect_equal([a: 1], [a: 1, b: 2])" "STOP(Dict: size mismatch (1 != 2)";
  test "expect_equal dict empty pass"
    "expect_equal([:], [:])" "PASS";
  test "expect_equal dict empty mismatch"
    "expect_equal([:], [a: 1])" "STOP(Dict: size mismatch (0 != 1)";
  test "expect_equal dict containing vector"
    "expect_equal([a: [1, 2]], [a: [1, 2]])" "PASS";

  (* expect_has_colnames *)
  test "expect_has_colnames pass"
    "df = to_dataframe([x: [1], y: [2], z: [3]]); expect_has_colnames(df, [\"x\", \"z\"])" "PASS";
  test "expect_has_colnames single string pass"
    "df = to_dataframe([x: [1], y: [2]]); expect_has_colnames(df, \"x\")" "PASS";
  test "expect_has_colnames stop"
    "df = to_dataframe([x: [1], y: [2]]); expect_has_colnames(df, [\"x\", \"w\"])" "STOP(Missing expected column(s)";
  test "expect_has_colnames NA"
    "expect_has_colnames(NA, [\"x\"])" "HOLD(";

  (* expect_unique *)
  test "expect_unique vector pass"
    "v = [1, 2, 3, 4]; expect_unique(v)" "PASS";
  test "expect_unique vector stop"
    "v = [1, 2, 3, 2]; expect_unique(v)" "STOP(Found duplicate value `2` at index 3";
  test "expect_unique dataframe pass"
    "df = to_dataframe([x: [1, 2], y: [3, 4]]); expect_unique(df)" "PASS";
  test "expect_unique dataframe stop"
    "df = to_dataframe([x: [1, 1], y: [2, 2]]); expect_unique(df)" "STOP(DataFrame contains duplicate row at index 1";
  (* check *)
  test "check pass"
    "check(expect_equal(1, 1))" "true";
  test "check failure"
    "check(expect_equal(1, 2))" "Error(RuntimeError: \"Assertion failed: `1` != `2`.\")";

  Printf.printf "\n"
