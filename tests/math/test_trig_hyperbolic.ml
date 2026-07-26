let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Phase 4 — Math: Trig & Hyperbolic Functions:\n";

  Printf.printf "  tan():\n";
  test "tan(0) = 0" "tan(0.0)" "0.";
  test "tan(0.785398) ~ 1" "tan(0.785398) > 0.99 && tan(0.785398) < 1.01" "true";
  test "tan(NA) errors" "tan(NA)" {|Error(TypeError: "Function `tan` encountered NA value. Handle missingness explicitly.")|};
  test "tan(NA, na_ignore = true) returns NA" "tan(NA, na_ignore = true)" "NA";
  test "tan rejects string" "tan(\"hello\")" {|Error(TypeError: "Function `tan` expects numeric input.")|};
  print_newline ();

  Printf.printf "  sinh(), cosh(), tanh():\n";
  test "sinh(0) = 0" "sinh(0.0)" "0.";
  test "cosh(0) = 1" "cosh(0.0)" "1.";
  test "tanh(0) = 0" "tanh(0.0)" "0.";
  print_newline ();

  Printf.printf "  asin(), acos(), atan():\n";
  test "asin(0) = 0" "asin(0.0)" "0.";
  test "acos(1) = 0" "acos(1.0)" "0.";
  test "atan(0) = 0" "atan(0.0)" "0.";
  print_newline ();

  Printf.printf "  asinh(), acosh(), atanh():\n";
  test "asinh(0) = 0" "asinh(0.0)" "0.";
  test "acosh(1) = 0" "acosh(1.0)" "0.";
  test "atanh(0) = 0" "atanh(0.0)" "0.";
  print_newline ();

  Printf.printf "  iota():\n";
  test "iota(5) returns vector of length 5" "length(iota(5))" "5";
  test "iota(5) sum is 5" "sum(iota(5))" "5.";
  test "iota(0) returns empty vector" "length(iota(0))" "0";
  test "iota(-1) errors" "iota(-1)" {|Error(ValueError: "iota expects a non-negative integer.")|};
  test "iota rejects non-integer" "iota(\"hello\")" {|Error(TypeError: "iota expects a single Integer argument.")|};
  print_newline ();
  print_newline ()
