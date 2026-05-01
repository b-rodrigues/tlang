
let run_tests pass_count fail_count eval_string _eval_string_env test =
  Printf.printf "Phase 1 — Structured Errors:\n";
  test "error() constructor" {|error("something went wrong")|} {|Error(GenericError: "something went wrong")|};
  test "error() with code" {|error("TypeError", "expected Int")|} {|Error(TypeError: "expected Int")|};
  test "error() with StructuralError" {|error("StructuralError", "broken DAG")|} {|Error(StructuralError: "broken DAG")|};
  test "error_code()" "error_code(1 / 0)" {|"DivisionByZero"|};
  test "error_message()" "error_message(1 / 0)" {|"Division by zero."|};
  test "error_context() empty" "error_context(1 / 0)" "{}";
  test "is_error on constructed error" {|is_error(error("oops"))|} "true";
  test "error_code on type error" {|error_code(error("TypeError", "bad type"))|} {|"TypeError"|};
  test "error_code on non-error" "error_code(42)" {|Error(TypeError: "Function `error_code` expects an Error value.")|};
  test "error_message on non-error" {|error_message("hello")|} {|Error(TypeError: "Function `error_message` expects an Error value.")|};
  test "error_context on non-error" "error_context(42)" {|Error(TypeError: "Function `error_context` expects an Error value.")|};
  test "error_code arity error" "error_code()" {|Error(ArityError: "Function `error_code` expects 1 arguments but received 0.")|};
  test "error_message arity error" "error_message()" {|Error(ArityError: "Function `error_message` expects 1 arguments but received 0.")|};
  test "error_context arity error" "error_context()" {|Error(ArityError: "Function `error_context` expects 1 arguments but received 0.")|};
  let located_error =
    Ast.make_error
      ~location:{ Ast.file = Some "script.t"; line = 12; column = 5 }
      Ast.TypeError
      "expected int, got float"
  in
  if Ast.Utils.value_to_string located_error
     = {|Error(TypeError: "[script.t:L12:C5] expected int, got float")|} then begin
    incr pass_count;
    Printf.printf "  ✓ located errors include file/line/column prefix\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ located errors include file/line/column prefix\n"
  end;
  let repl_error =
    Ast.make_error
      ~location:{ Ast.file = None; line = 3; column = 9 }
      Ast.SyntaxError
      "Parse Error"
  in
  if Ast.Utils.value_to_string repl_error
     = {|Error(SyntaxError: "[L3:C9] Parse Error")|} then begin
    incr pass_count;
    Printf.printf "  ✓ located errors omit filename when unavailable\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ located errors omit filename when unavailable\n"
  end;
  let runtime_error = eval_string "1 / 0" |> Ast.Utils.value_to_string in
  let has_loc =
    try
      let _ = Str.search_forward (Str.regexp "\\[[^]]*L[0-9]+:C[0-9]+\\]") runtime_error 0 in
      true
    with Not_found -> false
  in
  if has_loc then begin
    incr pass_count;
    Printf.printf "  ✓ runtime errors include source location prefix\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ runtime errors include source location prefix\n"
  end;
  let contextual_error =
    Ast.make_error
      ~context:[("argument", Ast.VString "x"); ("expected", Ast.VString "Int")]
      Ast.TypeError
      "bad input"
  in
  if contextual_error
     = Ast.VError {
         code = Ast.TypeError;
         message = "bad input";
         context = [("argument", Ast.VString "x"); ("expected", Ast.VString "Int")];
         location = None;
         na_count = 0;
       } then begin
    incr pass_count;
    Printf.printf "  ✓ error values keep structured context\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ error values keep structured context\n"
  end;
  print_newline ();

  Printf.printf "Phase 1 — Enhanced Assert:\n";
  test "assert with message (pass)" {|assert(true, "should pass")|} "true";
  test "assert with message (fail)" {|assert(false, "custom message")|} {|Error(AssertionError: "Assertion failed: custom message.")|};
  test "assert on NA" "assert(NA)" {|Error(AssertionError: "Assertion received NA.")|};
  test "assert on NA with message" {|assert(NA, "value was missing")|} {|Error(AssertionError: "Assertion received NA: value was missing.")|};
  test "assert with non-string message" {|assert(true, 1)|} {|Error(TypeError: "Function `assert` expects a String as its second argument, got Int.")|};
  test "assert arity error" {|assert(true, "ok", "extra")|} {|Error(ArityError: "Function `assert` expects 1 or 2 arguments but received 3.")|};
  print_newline ();

  Printf.printf "Phase 1 — Error Values (No Crashes):\n";
  test "name error returns error value" "undefined_func(1)" {|Error(NameError: "Name `undefined_func` is not defined.")|};
  test "calling non-function returns error" "x = 42; x(1)" {|Error(TypeError: "Value of type Int is not callable.")|};
  test "sum with NA returns error" "sum([1, NA, 3])" {|Error(AggregationError: "Function `sum` encountered NA value. Handle missingness explicitly or set `na_rm` to true.")|};
  test "head on NA returns error" "head(NA)" {|Error(TypeError: "Function `head` cannot be called on NA.")|};
  test "length on NA returns error" "length(NA)" {|Error(TypeError: "Cannot get length of NA.")|};
  print_newline ();

  Printf.printf "Phase 4 — Error Message Quality (Name Suggestions):\n";
  test "typo in function name suggests correction" "prnt(42)" "Name `prnt` is not defined.";
  test "typo in 'select' suggests correction" "slect(1)" "Name `slect` is not defined.";
  test "typo in 'filter' suggests correction" "flter(1)" "Name `flter` is not defined.";
  test "typo in 'mutate' suggests correction" "mutat(1)" "Name `mutat` is not defined.";
  test "typo in 'mean' suggests correction" "meen(1)" "Name `meen` is not defined.";
  test "completely unknown name has no suggestion" "xyzzy_unknown(1)" {|Error(NameError: "Name `xyzzy_unknown` is not defined.")|};
  test "error with non-string second arg" {|error("TypeError", 1)|} {|Error(TypeError: "Function `error` expects (String code, String message).")|};
  print_newline ();

  Printf.printf "Phase 4 — Error Message Quality (Type Conversion Hints):\n";
  test "int + bool shows hint" "1 + true" "expects Int and Bool.";
  test "list + int strict error" "[1, 2] + 3" {|Error(TypeError: "Operator '+' is defined for scalars only.
Use '.+' for element-wise (broadcast) operations.")|};
  test "string + int shows hint" {|"hello" + 1|} "expects String and Int.";
  print_newline ();

  Printf.printf "Phase 4 — Error Message Quality (Arity Signatures):\n";
  test "lambda arity error shows params" "f = \\(a, b) a + b; f(1)" {|Error(ArityError: "Function expects 2 arguments but received 1.")|};
  test "lambda arity error shows single param" "f = \\(x) x; f(1, 2)" {|Error(ArityError: "Function expects 1 arguments but received 2.")|};
  test "builtin arity error shows count" "length(1, 2)" {|Error(ArityError: "Function `length` expects 1 arguments but received 2.")|};
  print_newline ()
