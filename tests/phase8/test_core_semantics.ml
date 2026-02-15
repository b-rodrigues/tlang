(* tests/phase8/test_core_semantics.ml *)
(* Phase 8: Additional unit tests for core semantics *)
(* Validates edge cases and invariants across the language *)

let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Phase 8 — Core Semantics: Expression evaluation:\n";

  (* Nested arithmetic *)
  test "nested arithmetic" "((2 + 3) * (4 - 1)) / 5" "3.";
  test "float precision" "0.1 + 0.2" "0.3";
  test "int division" "7 / 2" "3.5";
  test "negative result" "3 - 10" "-7";
  test "multiply by zero" "42 * 0" "0";
  test "string repeat via concat error" {|"ha" + "ha" + "ha"|} {|Error(TypeError: "String concatenation with '+' is not supported. Use 'join([a, b], sep)' or 'paste(a, b, sep)' instead.")|};
  print_newline ();

  Printf.printf "Phase 8 — Core Semantics: Variable scoping:\n";

  (* Variable immutability *)
  test "variable immutability" "x = 1; x = 2; x"
    {|Error(NameError: "Cannot reassign immutable variable 'x'. Use ':=' to overwrite.")|};
  test "variable overwrite with :=" "x = 1; x := 2; x" "2";
  test "variable in expression" "a = 3; b = 4; a * b + 1" "13";
  test "variable chain" "x = 1; y = x + 1; z = y + 1; z" "3";
  print_newline ();

  Printf.printf "Phase 8 — Core Semantics: Function edge cases:\n";

  (* Function identity *)
  test "identity function" "id = \\(x) x; id(42)" "42";
  test "identity on string" {|id = \(x) x; id("hello")|} {|"hello"|};
  test "identity on bool" "id = \\(x) x; id(true)" "true";
  test "identity on list" "id = \\(x) x; id([1, 2])" "[1, 2]";

  (* Higher-order functions *)
  test "function returning function" "f = \\(x) \\(y) x + y; g = f(10); g(5)" "15";
  test "immediately invoked lambda" "(\\(x) x * 2)(5)" "10";
  test "nested closure" "a = 1; f = \\(x) \\(y) x + y + a; f(2)(3)" "6";
  print_newline ();

  Printf.printf "Phase 8 — Core Semantics: Pipe operator edge cases:\n";

  test "pipe to identity" "42 |> \\(x) x" "42";
  test "long pipe chain" "1 |> \\(n) n + 1 |> \\(m) m + 1 |> \\(p) p + 1" "4";
  test "pipe with list operations"
    "[1, 2, 3] |> map(\\(n) n * 2) |> map(\\(m) m + 1) |> sum"
    "15";
  print_newline ();

  Printf.printf "Phase 8 — Core Semantics: Conditional edge cases:\n";

  test "nested conditionals" "if (true) (if (false) 1 else 2) else 3" "2";
  test "conditional with comparison" "x = 5; if ((x > 3) && (x < 10)) \"in range\" else \"out\"" {|"in range"|};
  test "non-bool if condition"
    "if (1) 42 else 0"
    {|Error(TypeError: "If condition must be Bool, got Int")|};
  print_newline ();

  Printf.printf "Phase 8 — Core Semantics: List edge cases:\n";

  test "nested list" "[[1, 2], [3, 4]]" "[[1, 2], [3, 4]]";
  test "mixed type list" {|[1, "two", true, null]|} {|[1, "two", true, null]|};
  test "empty list length" "length([])" "0";
  test "head of single element" "head([42])" "42";
  test "tail of single element" "tail([42])" "[]";
  test "sum of empty list" "sum([])" "0";
  test "map on empty list" "map([], \\(x) x)" "[]";
  print_newline ();

  Printf.printf "Phase 8 — Core Semantics: Dict edge cases:\n";

  test "empty block (is null)" "{}" "null";
  test "dict with computed values" "x = 10; {a: x, b: x * 2}" {|{`a`: 10, `b`: 20}|};
  test "nested dict" {|{outer: {inner: 42}}.outer.inner|} "42";
  print_newline ();

  Printf.printf "Phase 8 — Core Semantics: Error invariants:\n";

  (* Error propagation through binary operations *)
  test "error + value" "(1 / 0) + 5" {|Error(DivisionByZero: "Division by zero.")|};
  test "value + error" "5 + (1 / 0)" {|Error(DivisionByZero: "Division by zero.")|};
  test "error * error" "(1 / 0) * (1 / 0)" {|Error(DivisionByZero: "Division by zero.")|};

  (* Type errors *)
  (* Note: Hint tests might fail if error messages changed slightly, so checking exact output is brittle.
     But we expect TypeErrors, not DivisionByZero for type mismatches. *)
  test "int + bool error" "1 + true" {|Error(TypeError: "Operator `+` expects Int and Bool.
Hint: Booleans and numbers cannot be combined in arithmetic. Use if-else to branch on boolean values.")|};
  test "bool * string error" {|true * "hello"|} {|Error(TypeError: "Operator `*` expects Bool and String.")|};

  (* Name errors *)
  test "undefined variable" "undefined_var" "undefined_var";
  test "undefined function call" "no_such_func(1)" {|Error(NameError: "Name `no_such_func` is not defined.")|};
  test "call non-function" "x = 42; x(1)" {|Error(TypeError: "Value of type Int is not callable.")|};
  print_newline ();

  Printf.printf "Phase 8 — Core Semantics: NA invariants:\n";

  (* NA doesn't propagate *)
  test "NA + NA is error" "NA + NA" {|Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "NA in conditional is error" "if (NA) 1 else 2" {|Error(TypeError: "Cannot use NA as a condition")|};
  test "is_na identity" "is_na(NA) && !is_na(42)" "true";

  (* Typed NA *)
  test "typed NAs are all NA" "is_na(na_int()) && is_na(na_float()) && is_na(na_bool()) && is_na(na_string())" "true";
  print_newline ();

  Printf.printf "Phase 8 — Core Semantics: Type introspection:\n";

  test "type of lambda" "type(\\(x) x)" {|"Function"|};
  test "type of builtin" "type(print)" {|"BuiltinFunction"|};
  test "type of vector" {|type(seq(1, 3))|} {|"List"|};
  test "type of error" "type(1 / 0)" {|"Error"|};
  test "type of null" "type(null)" {|"Null"|};
  test "type of NA" "type(NA)" {|"NA"|};
  test "type of pipeline" "type(pipeline { x = 1 })" {|"Pipeline"|};
  test "type of intent" {|type(intent { a: "1" })|} {|"Intent"|};
  print_newline ()
