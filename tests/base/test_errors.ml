let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Phase 1 — Structured Errors:\n";
  test "error() constructor" {|error("something went wrong")|} {|Error(GenericError: "something went wrong")|};
  test "error() with code" {|error("TypeError", "expected Int")|} {|Error(TypeError: "expected Int")|};
  test "error_code()" "error_code(1 / 0)" {|"DivisionByZero"|};
  test "error_message()" "error_message(1 / 0)" {|"Division by zero."|};
  test "error_context() empty" "error_context(1 / 0)" "{}";
  test "is_error on constructed error" {|is_error(error("oops"))|} "true";
  test "error_code on type error" {|error_code(error("TypeError", "bad type"))|} {|"TypeError"|};
  test "error_code on non-error" "error_code(42)" {|Error(TypeError: "Function `error_code` expects an Error value.")|};
  test "error_message on non-error" {|error_message("hello")|} {|Error(TypeError: "Function `error_message` expects an Error value.")|};
  print_newline ();

  Printf.printf "Phase 1 — Enhanced Assert:\n";
  test "assert with message (pass)" {|assert(true, "should pass")|} "true";
  test "assert with message (fail)" {|assert(false, "custom message")|} {|Error(AssertionError: "Assertion failed: custom message.")|};
  test "assert on NA" "assert(NA)" {|Error(AssertionError: "Assertion received NA.")|};
  test "assert on NA with message" {|assert(NA, "value was missing")|} {|Error(AssertionError: "Assertion received NA: value was missing.")|};
  print_newline ();

  Printf.printf "Phase 1 — Error Values (No Crashes):\n";
  test "name error returns error value" "undefined_func(1)" {|Error(NameError: "Name `undefined_func` is not defined.")|};
  test "calling non-function returns error" "x = 42; x(1)" {|Error(TypeError: "Value of type Int is not callable.")|};
  test "sum with NA returns error" "sum([1, NA, 3])" {|Error(TypeError: "Function `sum` encountered NA value. Handle missingness explicitly.")|};
  test "head on NA returns error" "head(NA)" {|Error(TypeError: "Function `head` cannot be called on NA.")|};
  test "length on NA returns error" "length(NA)" {|Error(TypeError: "Cannot get length of NA.")|};
  print_newline ();

  Printf.printf "Phase 4 — Error Message Quality (Name Suggestions):\n";
  test "typo in function name suggests correction" "prnt(42)" {|Error(NameError: "Name `prnt` is not defined.
Did you mean `print`?")|};
  test "typo in 'select' suggests correction" "slect(1)" {|Error(NameError: "Name `slect` is not defined.
Did you mean `select`?")|};
  test "typo in 'filter' suggests correction" "flter(1)" {|Error(NameError: "Name `flter` is not defined.
Did you mean `filter`?")|};
  test "typo in 'mutate' suggests correction" "mutat(1)" {|Error(NameError: "Name `mutat` is not defined.
Did you mean `mutate`?")|};
  test "typo in 'mean' suggests correction" "meen(1)" {|Error(NameError: "Name `meen` is not defined.
Did you mean `mean`?")|};
  test "completely unknown name has no suggestion" "xyzzy_unknown(1)" {|Error(NameError: "Name `xyzzy_unknown` is not defined.")|};
  print_newline ();

  Printf.printf "Phase 4 — Error Message Quality (Type Conversion Hints):\n";
  test "int + bool shows hint" "1 + true" {|Error(TypeError: "Operator `+` expects Int and Bool.
Hint: Booleans and numbers cannot be combined in arithmetic. Use if-else to branch on boolean values.")|};
  test "list + int strict error" "[1, 2] + 3" {|Error(TypeError: "Operator '+' is defined for scalars only.
Use '.+' for element-wise (broadcast) operations.")|};
  test "string + int shows hint" {|"hello" + 1|} {|Error(TypeError: "Operator `+` expects String and Int.
Hint: Strings cannot be used in arithmetic. Convert with int() or float() if available, or check your data types.")|};
  print_newline ();

  Printf.printf "Phase 4 — Error Message Quality (Arity Signatures):\n";
  test "lambda arity error shows params" "f = \\(a, b) a + b; f(1)" {|Error(ArityError: "Function expects 2 arguments but received 1.")|};
  test "lambda arity error shows single param" "f = \\(x) x; f(1, 2)" {|Error(ArityError: "Function expects 1 arguments but received 2.")|};
  test "builtin arity error shows count" "length(1, 2)" {|Error(ArityError: "Function expects 1 arguments but received 2.")|};
  print_newline ()
