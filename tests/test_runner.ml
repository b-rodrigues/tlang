(* tests/test_runner.ml *)
(* Simple test runner for T language Phase 0 *)

let pass_count = ref 0
let fail_count = ref 0

let eval_string input =
  let env = Eval.initial_env () in
  let lexbuf = Lexing.from_string input in
  let program = Parser.program Lexer.token lexbuf in
  let (result, _env) = Eval.eval_program program env in
  result

let test name input expected =
  let result = try
    let v = eval_string input in
    Ast.Utils.value_to_string v
  with e ->
    Printf.sprintf "EXCEPTION: %s" (Printexc.to_string e)
  in
  if result = expected then begin
    incr pass_count;
    Printf.printf "  ✓ %s\n" name
  end else begin
    incr fail_count;
    Printf.printf "  ✗ %s\n    Expected: %s\n    Got:      %s\n" name expected result
  end

let () =
  Printf.printf "\n=== T Language Phase 0 Tests ===\n\n";

  (* --- Arithmetic --- *)
  Printf.printf "Arithmetic:\n";
  test "integer addition" "1 + 2" "3";
  test "integer subtraction" "10 - 3" "7";
  test "integer multiplication" "4 * 5" "20";
  test "integer division" "15 / 3" "5";
  test "float addition" "1.5 + 2.5" "4.";
  test "mixed int+float" "1 + 2.5" "3.5";
  test "operator precedence" "2 + 3 * 4" "14";
  test "parentheses" "(2 + 3) * 4" "20";
  test "unary minus" "0 - 5" "-5";
  test "division by zero" "1 / 0" "Error(\"Division by zero\")";
  test "string concatenation" {|"hello" + " world"|} {|"hello world"|};
  print_newline ();

  (* --- Comparisons --- *)
  Printf.printf "Comparisons:\n";
  test "equality true" "1 == 1" "true";
  test "equality false" "1 == 2" "false";
  test "not equal" "1 != 2" "true";
  test "less than" "1 < 2" "true";
  test "greater than" "3 > 2" "true";
  test "less or equal" "2 <= 2" "true";
  test "greater or equal" "3 >= 3" "true";
  print_newline ();

  (* --- Logical --- *)
  Printf.printf "Logical:\n";
  test "and true" "true and true" "true";
  test "and false" "true and false" "false";
  test "or true" "false or true" "true";
  test "not true" "not true" "false";
  test "not false" "not false" "true";
  print_newline ();

  (* --- Variables --- *)
  Printf.printf "Variables:\n";
  test "assignment and use" "x = 42; x" "42";
  test "variable arithmetic" "x = 10; y = 20; x + y" "30";
  test "reassignment" "x = 1; x = 2; x" "2";
  print_newline ();

  (* --- Functions --- *)
  Printf.printf "Functions:\n";
  test "lambda definition and call" "f = \\(x) x + 1; f(5)" "6";
  test "function keyword" "f = function(x) x * 2; f(3)" "6";
  test "two-arg function" "add = \\(a, b) a + b; add(3, 4)" "7";
  test "closure" "make_adder = \\(n) \\(x) x + n; add5 = make_adder(5); add5(10)" "15";
  test "arity error" "f = \\(x) x; f(1, 2)" {|Error("Arity Error: Expected 1 arguments but got 2")|};
  print_newline ();

  (* --- Pipe Operator --- *)
  Printf.printf "Pipe Operator:\n";
  test "pipe to function" "double = \\(x) x * 2; 5 |> double" "10";
  test "pipe with args" "add = \\(a, b) a + b; 5 |> add(3)" "8";
  test "pipe chain" "double = \\(x) x * 2; inc = \\(x) x + 1; 5 |> double |> inc" "11";
  test "pipe to builtin" "42 |> type" {|"Int"|};
  test "pipe chain across lines"
    "[1, 2, 3]\n  |> map(\\(x) x * x)\n  |> sum"
    "14";
  print_newline ();

  (* --- If/Else --- *)
  Printf.printf "If/Else:\n";
  test "if true" "if (true) 1 else 2" "1";
  test "if false" "if (false) 1 else 2" "2";
  test "if with comparison" "if (3 > 2) 10 else 20" "10";
  print_newline ();

  (* --- Lists --- *)
  Printf.printf "Lists:\n";
  test "empty list" "[]" "[]";
  test "int list" "[1, 2, 3]" "[1, 2, 3]";
  test "named list" "[a: 1, b: 2]" "[a: 1, b: 2]";
  test "length" "length([1, 2, 3])" "3";
  test "head" "head([1, 2, 3])" "1";
  test "tail" "tail([1, 2, 3])" "[2, 3]";
  print_newline ();

  (* --- Dicts --- *)
  Printf.printf "Dicts:\n";
  test "dict literal" {|{x: 1, y: 2}|} {|{`x`: 1, `y`: 2}|};
  test "dict dot access" "{x: 42, y: 99}.x" "42";
  test "dict missing key" "{x: 1}.z" {|Error("Key Error: key 'z' not found in dict")|};
  print_newline ();

  (* --- Builtins --- *)
  Printf.printf "Builtins:\n";
  test "type of int" "type(42)" {|"Int"|};
  test "type of string" {|type("hello")|} {|"String"|};
  test "type of bool" "type(true)" {|"Bool"|};
  test "type of list" "type([1])" {|"List"|};
  test "assert true" "assert(true)" "true";
  test "assert false" "assert(false)" {|Error("Assertion failed")|};
  test "is_error on error" "is_error(1 / 0)" "true";
  test "is_error on value" "is_error(42)" "false";
  test "seq" "seq(1, 3)" "[1, 2, 3]";
  test "sum" "sum([1, 2, 3, 4, 5])" "15";
  test "map" "map([1, 2, 3], \\(x) x * x)" "[1, 4, 9]";
  print_newline ();

  (* --- Error Handling --- *)
  Printf.printf "Error Handling:\n";
  test "error propagation in addition" "(1 / 0) + 1" {|Error("Division by zero")|};
  test "error in list" "[1, 1/0, 3]" {|Error("Division by zero")|};
  print_newline ();

  (* --- Summary --- *)
  let total = !pass_count + !fail_count in
  Printf.printf "=== Results: %d/%d passed ===\n" !pass_count total;
  if !fail_count > 0 then begin
    Printf.printf "FAILED: %d tests failed\n" !fail_count;
    exit 1
  end else
    Printf.printf "All tests passed!\n"
