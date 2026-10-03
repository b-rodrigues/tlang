let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env _test test_env test_equal =
  Printf.printf "If/Else:\n";
  let env = Packages.init_env () in
  test_equal env "if true" "if (true) 1 else 2" "1";
  test_equal env "if false" "if (false) 1 else 2" "2";
  test_equal env "if with comparison" "if (3 > 2) 10 else 20" "10";
  test_env env "if NA condition is error" "if (NA) 1 else 2" "Cannot use NA as a condition";
  test_env env "if non-bool condition is error" "if (1) 1 else 2" "`if` condition expected Bool, got Int.";
  test_env env "if error in then-branch propagates" "if (true) (1/0) else 2" "Division by zero.";
  test_env env "if error in else-branch propagates" "if (false) 1 else (1/0)" "Division by zero.";
  test_equal env "nested if else-if" "if (false) 1 else if (true) 2 else 3" "2";
  print_newline ()
