let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Logical:\n";
  test "and true" "true and true" "true";
  test "and false" "true and false" "false";
  test "or true" "false or true" "true";
  test "not true" "not true" "false";
  test "not false" "not false" "true";
  print_newline ()
