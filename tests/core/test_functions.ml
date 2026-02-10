let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Functions:\n";
  test "lambda definition and call" "f = \\(x) x + 1; f(5)" "6";
  test "function keyword" "f = function(x) x * 2; f(3)" "6";
  test "two-arg function" "add = \\(a, b) a + b; add(3, 4)" "7";
  test "closure" "make_adder = \\(n) \\(x) x + n; add5 = make_adder(5); add5(10)" "15";
  test "arity error" "f = \\(x) x; f(1, 2)" {|Error(ArityError: "Expected 1 arguments (x) but got 2")|};
  print_newline ()
