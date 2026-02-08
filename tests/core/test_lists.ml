let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Lists:\n";
  test "empty list" "[]" "[]";
  test "int list" "[1, 2, 3]" "[1, 2, 3]";
  test "named list" "[a: 1, b: 2]" "[a: 1, b: 2]";
  test "length" "length([1, 2, 3])" "3";
  test "head" "head([1, 2, 3])" "1";
  test "tail" "tail([1, 2, 3])" "[2, 3]";
  print_newline ()
