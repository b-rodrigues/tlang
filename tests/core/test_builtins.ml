let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Builtins:\n";
  test "type of int" "type(42)" {|"Int"|};
  test "type of string" {|type("hello")|} {|"String"|};
  test "type of bool" "type(true)" {|"Bool"|};
  test "type of list" "type([1])" {|"List"|};
  test "assert true" "assert(true)" "true";
  test "assert false" "assert(false)" {|Error(AssertionError: "Assertion failed")|};
  test "is_error on error" "is_error(1 / 0)" "true";
  test "is_error on value" "is_error(42)" "false";
  test "seq" "seq(1, 3)" "[1, 2, 3]";
  test "sum" "sum([1, 2, 3, 4, 5])" "15";
  test "map" "map([1, 2, 3], \\(x) x * x)" "[1, 4, 9]";
  print_newline ();

  Printf.printf "Error Handling:\n";
  test "error propagation in addition" "(1 / 0) + 1" {|Error(DivisionByZero: "Division by zero")|};
  test "error in list" "[1, 1/0, 3]" {|Error(DivisionByZero: "Division by zero")|};
  print_newline ()
