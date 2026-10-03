let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "If/Else:\n";
  test "if true" "if (true) 1 else 2" "1";
  test "if false" "if (false) 1 else 2" "2";
  test "if with comparison" "if (3 > 2) 10 else 20" "10";
  test "if NA condition is error" "if (NA) 1 else 2" "Cannot use NA as a condition";
  test "if non-bool condition is error" "if (1) 1 else 2" "`if` condition expected Bool, got Int.";
  test "if error in then-branch propagates" "if (true) (1/0) else 2" "Division by zero.";
  test "if error in else-branch propagates" "if (false) 1 else (1/0)" "Division by zero.";
  test "nested if else-if" "if (false) 1 else if (true) 2 else 3" "2";
  print_newline ()
