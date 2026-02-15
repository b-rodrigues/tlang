let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Arithmetic:\n";
  test "integer addition" "1 + 2" "3";
  test "integer subtraction" "10 - 3" "7";
  test "integer multiplication" "4 * 5" "20";
  test "integer division" "15 / 3" "5.";
  test "float addition" "1.5 + 2.5" "4.";
  test "mixed int+float" "1 + 2.5" "3.5";
  test "operator precedence" "2 + 3 * 4" "14";
  test "parentheses" "(2 + 3) * 4" "20";
  test "unary minus" "0 - 5" "-5";
  test "division by zero" "1 / 0" {|Error(DivisionByZero: "Division by zero.")|};
  test "string concatenation error" {|"hello" + " world"|} {|Error(TypeError: "String concatenation with '+' is not supported. Use 'join([a, b], sep)' or 'paste(a, b, sep)' instead.")|};
  print_newline ()
