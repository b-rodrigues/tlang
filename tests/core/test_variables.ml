let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Variables:\n";
  test "assignment and use" "x = 42; x" "42";
  test "variable arithmetic" "x = 10; y = 20; x + y" "30";
  test "reassignment with = is error" "x = 1; x = 2; x" "Cannot reassign immutable variable 'x'.";
  test "reassignment with := works" "x = 1; x := 2; x" "2";
  test "assignment returns NA" "x = 42" "NA";
  test "assignment of error returns error" "x = mean([1, NA, 3])" "encountered NA value.";
  test ":= on undefined variable is error" "y := 5" "Cannot overwrite 'y': variable not defined.";
  print_newline ()
