let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Testcraft — expect_equal:\n";

  test "expect_equal ints pass" "expect_equal(1, 1)" "PASS";
  test "expect_equal ints stop" "expect_equal(1, 2)" {|STOP(`1` != `2`)|};
  test "expect_equal floats pass" "expect_equal(1.0, 1.0)" "PASS";
  test "expect_equal floats within tolerance"
    "expect_equal(0.1 + 0.2, 0.3, tolerance = 1e-9)" "PASS";
  test "expect_equal floats stop" "expect_equal(1.0, 2.0)" "STOP(";
  test "expect_equal strings pass" {|expect_equal("a", "a")|} "PASS";
  test "expect_equal strings stop" {|expect_equal("a", "b")|} "STOP(";
  test "expect_equal actual NA holds" "expect_equal(NA, 1)" "HOLD(";
  test "expect_equal expected NA holds" "expect_equal(1, NA)" "HOLD(";
  test "expect_equal actual error stops"
    {|expect_equal(error("boom"), 1)|} "STOP(";
  test "expect_equal expected error stops"
    {|expect_equal(1, error("boom"))|} "STOP(";
  test "expect_equal type mismatch stops"
    {|expect_equal(1, "1")|} {|STOP(`1` (Int) != `"1"` (String))|};
  test "expect_equal bools pass" "expect_equal(true, true)" "PASS";

  test "assert of passing expect_equal" "assert(expect_equal(1, 1))" "true";
  test "assert of failing expect_equal"
    "assert(expect_equal(1, 2))" {|Error(AssertionError|};

  test "expect_pass on pass" "expect_pass(expect_equal(1, 1))" "true";
  test "expect_pass on stop" "expect_pass(expect_equal(1, 2))" "false";
  test "expect_fail on stop" "expect_fail(expect_equal(1, 2))" "true";
  test "expect_fail on pass" "expect_fail(expect_equal(1, 1))" "false";
  test "expect_msg on stop" "expect_msg(expect_equal(1, 2))" {|`1` != `2`|};

  Printf.printf "\n"
