let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Comparisons:\n";
  test "equality true" "1 == 1" "true";
  test "equality false" "1 == 2" "false";
  test "not equal" "1 != 2" "true";
  test "less than" "1 < 2" "true";
  test "greater than" "3 > 2" "true";
  test "less or equal" "2 <= 2" "true";
  test "greater or equal" "3 >= 3" "true";
  print_newline ()
