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
  test "list comprehension maps over seq"
    "[x * 10 for x in seq(1, 5)]"
    "[10, 20, 30, 40, 50]";
  test "list comprehension filters values"
    "[x for x in seq(1, 6) if x % 2 == 0]"
    "[2, 4, 6]";
  test "list comprehension supports nested for clauses"
    "[x + y for x in [1, 2] for y in [10, 20]]"
    "[11, 21, 12, 22]";
  test "list comprehension captures surrounding bindings"
    "scale = 3; [x * scale for x in [1, 2, 3]]"
    "[3, 6, 9]";
  test "list comprehension rejects non-iterables"
    "[x for x in 1]"
    {|Error(TypeError: "List comprehension `for` clauses expect a List or Vector, got Int.")|};
  test "list comprehension filter requires bool"
    "[x for x in [1, 2, 3] if 1]"
    {|Error(TypeError: "List comprehension filter must evaluate to Bool, got Int.")|};
  print_newline ()
