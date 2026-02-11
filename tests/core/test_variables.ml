let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Variables:\n";
  test "assignment and use" "x = 42; x" "42";
  test "variable arithmetic" "x = 10; y = 20; x + y" "30";
  test "reassignment with = is error" "x = 1; x = 2; x"
    {|Error(NameError: "Cannot reassign immutable variable 'x'. Use ':=' to overwrite.")|};
  test "reassignment with := works" "x = 1; x := 2; x" "2";
  test "assignment returns null" "x = 42" "null";
  test "assignment of error returns error" "x = mean([1, NA, 3])"
    {|Error(TypeError: "mean() encountered NA value. Handle missingness explicitly.")|};
  test ":= on undefined variable is error" "y := 5"
    {|Error(NameError: "Cannot overwrite 'y': variable not defined. Use '=' for first assignment.")|};
  print_newline ()
