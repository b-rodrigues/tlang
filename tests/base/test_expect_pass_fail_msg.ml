let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Testcraft — expect_pass, expect_fail, expect_msg:\n";

  (* === expect_pass === *)

  test "expect_pass on passing expect_equal"
    "expect_pass(expect_equal(1, 1))" "true";
  test "expect_pass on stopping expect_equal"
    "expect_pass(expect_equal(1, 2))" "false";
  test "expect_pass on holding expect_equal (actual NA)"
    "expect_pass(expect_equal(NA, 1))" "false";
  test "expect_pass on holding expect_equal (expected NA)"
    "expect_pass(expect_equal(1, NA))" "false";
  test "expect_pass on passing expect_lt"
    "expect_pass(expect_lt(1, 2))" "true";
  test "expect_pass on stopping expect_lt"
    "expect_pass(expect_lt(2, 1))" "false";
  test "expect_pass on non-Expect type error"
    "expect_pass(42)" "Error(TypeError:";
  test "expect_pass with no args arity error"
    "expect_pass()" "Error(ArityError:";
  test "expect_pass with too many args arity error"
    "expect_pass(expect_equal(1, 1), extra)" "Error(ArityError:";

  (* === expect_fail === *)

  test "expect_fail on stopping expect_equal"
    "expect_fail(expect_equal(1, 2))" "true";
  test "expect_fail on passing expect_equal"
    "expect_fail(expect_equal(1, 1))" "false";
  test "expect_fail on holding expect_equal (actual NA)"
    "expect_fail(expect_equal(NA, 1))" "true";
  test "expect_fail on holding expect_equal (expected NA)"
    "expect_fail(expect_equal(1, NA))" "true";
  test "expect_fail on stopping expect_lt"
    "expect_fail(expect_lt(2, 1))" "true";
  test "expect_fail on passing expect_lt"
    "expect_fail(expect_lt(1, 2))" "false";
  test "expect_fail on non-Expect type error"
    "expect_fail(42)" "Error(TypeError:";
  test "expect_fail with no args arity error"
    "expect_fail()" "Error(ArityError:";
  test "expect_fail with too many args arity error"
    "expect_fail(expect_equal(1, 2), extra)" "Error(ArityError:";

  (* === expect_msg === *)

  test "expect_msg on stopping expect_equal"
    "expect_msg(expect_equal(1, 2))" {|`1` != `2`|};
  test "expect_msg on holding expect_equal (actual NA)"
    "expect_msg(expect_equal(NA, 1))" "actual` is NA";
  test "expect_msg on holding expect_equal (expected NA)"
    "expect_msg(expect_equal(1, NA))" "expected` is NA";
  test "expect_msg on passing expect_equal returns error"
    "expect_msg(expect_equal(1, 1))" "Error(ValueError:";
  test "expect_msg on stopping expect_lt"
    "expect_msg(expect_lt(2, 1))" {|`2` < `1`|};
  test "expect_msg on stopping expect_gt"
    "expect_msg(expect_gt(1, 2))" {|`1` > `2`|};
  test "expect_msg on stopping expect_type"
    "expect_msg(expect_type(42, \"String\"))" "Int";
  test "expect_msg on non-Expect type error"
    "expect_msg(42)" "Error(TypeError:";
  test "expect_msg with no args arity error"
    "expect_msg()" "Error(ArityError:";
  test "expect_msg with too many args arity error"
    "expect_msg(expect_equal(1, 2), extra)" "Error(ArityError:";

  Printf.printf "\n"
