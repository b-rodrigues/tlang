let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env _test test_env test_equal =
  Printf.printf "Arithmetic:\n";
  let env = Packages.init_env () in
  test_equal env "integer addition" "1 + 2" "3";
  test_equal env "integer subtraction" "10 - 3" "7";
  test_equal env "integer multiplication" "4 * 5" "20";
  test_equal env "integer division" "15 / 3" "5.";
  test_equal env "float addition" "1.5 + 2.5" "4.";
  test_equal env "mixed int+float" "1 + 2.5" "3.5";
  test_equal env "operator precedence" "2 + 3 * 4" "14";
  test_equal env "parentheses" "(2 + 3) * 4" "20";
  test_equal env "unary minus" "-5" "-5";
  test_equal env "unary minus float" "-2.5" "-2.5";
  test_equal env "double negation" "-(-5)" "5";
  test_equal env "negated parentheses" "-(2 + 3)" "-5";
  test_env env "division by zero" "1 / 0" {|Error(DivisionByZero: "Division by zero.")|};
  test_env env "string concatenation error" {|"hello" + " world"|} {|Error(TypeError: "String concatenation with '+' is not supported. Use 'str_join([a, b], sep)' or 'paste(a, b, sep)' instead.")|};
  print_newline ()
