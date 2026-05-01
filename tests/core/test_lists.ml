let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Lists:\n";
  test "empty list" "[]" "[]";
  test "int list" "[1, 2, 3]" "[1, 2, 3]";
  test "dict in brackets" "[a: 1, b: 2]" "{`a`: 1, `b`: 2}";
  test "mixed list/dict is parse error" "[a: 1, 2]" {|EXCEPTION: Parser.Mixed_bracket_form|};
  test "length" "length([1, 2, 3])" "3";
  test "head" "head([1, 2, 3])" "1";
  test "tail" "tail([1, 2, 3])" "[2, 3]";
  test "head extra positional arity reports optional second arg"
    "head([1, 2, 3], 1, 0)"
    {|Error(ArityError: "Function `head` expects 2 arguments but received 3.")|};
  test "tail extra positional arity reports optional second arg"
    "tail([1, 2, 3], 1, 0)"
    {|Error(ArityError: "Function `tail` expects 2 arguments but received 3.")|};
  test "tail wrong type mentions vector support"
    {|tail("abc")|}
    {|Error(TypeError: "Function `tail` expects a DataFrame, List, or Vector.")|};
  
  Printf.printf "List Slicing Edge Cases:\n";
  test "head n=0" "head([1, 2, 3], n=0)" "[]";
  test "head n=1" "head([1, 2, 3], n=1)" "[1]";
  test "head n=10" "head([1, 2, 3], n=10)" "[1, 2, 3]";
  test "tail n=0" "tail([1, 2, 3], n=0)" "[]";
  test "tail n=1" "tail([1, 2, 3], n=1)" "[3]";
  test "tail n=10" "tail([1, 2, 3], n=10)" "[1, 2, 3]";
  test "head empty list" "head([], n=5)" "[]";
  test "tail empty list" "tail([], n=5)" "[]";
  print_newline ()
