(* tests/test_runner.ml *)
(* Test runner for T language Phase 0 + Phase 1 *)

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
  Printf.printf "\n=== T Language Phase 0 + Phase 1 Tests ===\n\n";

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
  test "division by zero" "1 / 0" {|Error(DivisionByZero: "Division by zero")|};
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
  test "arity error" "f = \\(x) x; f(1, 2)" {|Error(ArityError: "Expected 1 arguments but got 2")|};
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
  test "dict missing key" "{x: 1}.z" {|Error(KeyError: "key 'z' not found in dict")|};
  print_newline ();

  (* --- Builtins --- *)
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

  (* --- Error Handling --- *)
  Printf.printf "Error Handling:\n";
  test "error propagation in addition" "(1 / 0) + 1" {|Error(DivisionByZero: "Division by zero")|};
  test "error in list" "[1, 1/0, 3]" {|Error(DivisionByZero: "Division by zero")|};
  print_newline ();

  (* ============================================ *)
  (* --- Phase 1: NA Values and Missingness --- *)
  (* ============================================ *)
  Printf.printf "Phase 1 — NA Values:\n";
  test "NA literal" "NA" "NA";
  test "typed NA bool" "na_bool()" "NA(Bool)";
  test "typed NA int" "na_int()" "NA(Int)";
  test "typed NA float" "na_float()" "NA(Float)";
  test "typed NA string" "na_string()" "NA(String)";
  test "generic NA" "na()" "NA";
  test "is_na on NA" "is_na(NA)" "true";
  test "is_na on typed NA" "is_na(na_int())" "true";
  test "is_na on value" "is_na(42)" "false";
  test "is_na on null" "is_na(null)" "false";
  test "type of NA" "type(NA)" {|"NA"|};
  test "NA is falsy" "if (NA) 1 else 2" {|Error(TypeError: "Cannot use NA as a condition")|};
  test "NA equality is error" "NA == NA" {|Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "NA comparison with value is error" "NA == 1" {|Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 1 — No Implicit NA Propagation:\n";
  test "NA + int is error" "NA + 1" {|Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "int + NA is error" "1 + NA" {|Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "NA * float is error" "NA * 2.0" {|Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "negation of NA is error" "x = NA; 0 - x" {|Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  print_newline ();

  (* ============================================ *)
  (* --- Phase 1: Structured Errors --- *)
  (* ============================================ *)
  Printf.printf "Phase 1 — Structured Errors:\n";
  test "error() constructor" {|error("something went wrong")|} {|Error(GenericError: "something went wrong")|};
  test "error() with code" {|error("TypeError", "expected Int")|} {|Error(TypeError: "expected Int")|};
  test "error_code()" "error_code(1 / 0)" {|"DivisionByZero"|};
  test "error_message()" "error_message(1 / 0)" {|"Division by zero"|};
  test "error_context() empty" "error_context(1 / 0)" "{}";
  test "is_error on constructed error" {|is_error(error("oops"))|} "true";
  test "error_code on type error" {|error_code(error("TypeError", "bad type"))|} {|"TypeError"|};
  test "error_code on non-error" "error_code(42)" {|Error(TypeError: "error_code() expects an Error value")|};
  test "error_message on non-error" {|error_message("hello")|} {|Error(TypeError: "error_message() expects an Error value")|};
  print_newline ();

  Printf.printf "Phase 1 — Enhanced Assert:\n";
  test "assert with message (pass)" {|assert(true, "should pass")|} "true";
  test "assert with message (fail)" {|assert(false, "custom message")|} {|Error(AssertionError: "Assertion failed: custom message")|};
  test "assert on NA" "assert(NA)" {|Error(AssertionError: "Assertion received NA")|};
  test "assert on NA with message" {|assert(NA, "value was missing")|} {|Error(AssertionError: "Assertion received NA: value was missing")|};
  print_newline ();

  Printf.printf "Phase 1 — Error Values (No Crashes):\n";
  test "name error returns error value" "undefined_func(1)" {|Error(NameError: "'undefined_func' is not defined")|};
  test "calling non-function returns error" "x = 42; x(1)" {|Error(TypeError: "Cannot call Int as a function")|};
  test "sum with NA returns error" "sum([1, NA, 3])" {|Error(TypeError: "sum() encountered NA value. Handle missingness explicitly.")|};
  test "head on NA returns error" "head(NA)" {|Error(TypeError: "Cannot call head() on NA")|};
  test "length on NA returns error" "length(NA)" {|Error(TypeError: "Cannot get length of NA")|};
  print_newline ();

  (* --- Summary --- *)
  let total = !pass_count + !fail_count in
  Printf.printf "=== Results: %d/%d passed ===\n" !pass_count total;
  if !fail_count > 0 then begin
    Printf.printf "FAILED: %d tests failed\n" !fail_count;
    exit 1
  end else
    Printf.printf "All tests passed!\n"
