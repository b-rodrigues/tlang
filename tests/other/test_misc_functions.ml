let run_tests _pass_count _fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "Phase 5 — Other: str_sprintf, float_seq, explain_json:\n";

  Printf.printf "  str_sprintf():\n";
  test "str_sprintf with string substitution"
    "str_sprintf(\"hello %s\", \"world\")"
    {|"hello world"|};
  test "str_sprintf with integer substitution"
    "str_sprintf(\"%d + %d = %d\", 1, 2, 3)"
    {|"1 + 2 = 3"|};
  test "str_sprintf with float substitution"
    "str_sprintf(\"%f\", 3.14)"
    {|"3.14"|};
  test "str_sprintf with no args"
    "str_sprintf(\"no args\")"
    {|"no args"|};
  test "str_sprintf rejects non-string format"
    "str_sprintf(42)"
    {|Error(TypeError: "str_sprintf expects a format string as the first argument.")|};
  test "str_sprintf rejects not enough args"
    "str_sprintf(\"%s\")"
    {|Error(ValueError: "Not enough arguments for format string.")|};
  print_newline ();

  Printf.printf "  float_seq():\n";
  test "float_seq with 3 args returns list of correct length"
    "length(float_seq(0.0, 1.0, 5))"
    "5";
  test "float_seq with 2 args defaults to 100"
    "length(float_seq(0, 1))"
    "100";
  test "float_seq rejects non-numeric start"
    "float_seq(\"a\", \"b\")"
    {|Error(TypeError: "Function `float_seq` arguments must be numeric.")|};
  print_newline ();

  Printf.printf "  explain_json():\n";
  test "explain_json returns string"
    "type(explain_json(42))"
    {|"String"|};
  test "explain_json non-empty"
    "str_nchar(explain_json(42)) > 0"
    "true";
  print_newline ();
  print_newline ()
