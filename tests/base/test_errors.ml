
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

  Printf.printf "Filesystem Assert Helpers:\n";
  let temp_dir_root = Filename.get_temp_dir_name () in
  let temp_dir =
    Filename.concat temp_dir_root
      (Printf.sprintf "tlang-assert-tests-%d" (Unix.getpid ()))
  in
  (try Unix.mkdir temp_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let existing_file = Filename.concat temp_dir "artifact.txt" in
  let empty_file = Filename.concat temp_dir "empty.txt" in
  let missing_file = Filename.concat temp_dir "missing.txt" in
  let file_contents = "hello" in
  let oc = open_out existing_file in
  output_string oc file_contents;
  close_out oc;
  let oc_empty = open_out empty_file in
  close_out oc_empty;
  test "assert_file_exists passes on regular file"
    (Printf.sprintf {|assert_file_exists("%s")|} existing_file)
    "true";
  test "assert_file_exists fails on missing file"
    (Printf.sprintf {|assert_file_exists("%s")|} missing_file)
    (Printf.sprintf {|Error(AssertionError: "Expected file `%s` to exist.")|} missing_file);
  test "assert_file_exists accepts custom message"
    (Printf.sprintf {|assert_file_exists("%s", "output file missing")|} missing_file)
    {|Error(AssertionError: "Assertion failed: output file missing.")|};
  test "assert_file_exists rejects non-string message"
    (Printf.sprintf {|assert_file_exists("%s", 1)|} existing_file)
    {|Error(TypeError: "Function `assert_file_exists` expects a String as its second argument, got Int.")|};
  test "assert_dir_exists passes on directory"
    (Printf.sprintf {|assert_dir_exists("%s")|} temp_dir)
    "true";
  test "assert_dir_exists fails on file path"
    (Printf.sprintf {|assert_dir_exists("%s")|} existing_file)
    (Printf.sprintf {|Error(AssertionError: "Expected `%s` to be a directory.")|} existing_file);
  test "assert_dir_exists fails on missing directory"
    (Printf.sprintf {|assert_dir_exists("%s")|} missing_file)
    (Printf.sprintf {|Error(AssertionError: "Expected directory `%s` to exist.")|} missing_file);
  test "assert_dir_exists accepts custom message"
    (Printf.sprintf {|assert_dir_exists("%s", "artifact directory missing")|} existing_file)
    {|Error(AssertionError: "Assertion failed: artifact directory missing.")|};
  test "assert_dir_exists rejects non-string path"
    {|assert_dir_exists(1)|}
    {|Error(TypeError: "Function `assert_dir_exists` expects a String as its first argument, got Int.")|};
  test "assert_size_of_file passes on exact size"
    (Printf.sprintf {|assert_size_of_file("%s", %d)|} existing_file (String.length file_contents))
    "true";
  test "assert_size_of_file fails on wrong size"
    (Printf.sprintf {|assert_size_of_file("%s", 4)|} existing_file)
    (Printf.sprintf {|Error(AssertionError: "Expected file `%s` to have size 4 bytes but found 5 bytes.")|} existing_file);
  test "assert_size_of_file accepts custom message"
    (Printf.sprintf {|assert_size_of_file("%s", 4, "artifact has wrong size")|} existing_file)
    {|Error(AssertionError: "Assertion failed: artifact has wrong size.")|};
  test "assert_size_of_file rejects negative size"
    (Printf.sprintf {|assert_size_of_file("%s", -1)|} existing_file)
    {|Error(ValueError: "Function `assert_size_of_file` expects a non-negative file size.")|};
  test "assert_size_of_file rejects non-string path"
    {|assert_size_of_file(1, 0)|}
    {|Error(TypeError: "Function `assert_size_of_file` expects a String as its first argument, got Int.")|};
  test "assert_size_of_file rejects non-int size"
    (Printf.sprintf {|assert_size_of_file("%s", "five")|} existing_file)
    {|Error(TypeError: "Function `assert_size_of_file` expects an Int as its second argument, got String.")|};
  test "assert_non_empty_file passes on non-empty file"
    (Printf.sprintf {|assert_non_empty_file("%s")|} existing_file)
    "true";
  test "assert_non_empty_file fails on empty file"
    (Printf.sprintf {|assert_non_empty_file("%s")|} empty_file)
    (Printf.sprintf {|Error(AssertionError: "Expected file `%s` to be non-empty.")|} empty_file);
  test "assert_non_empty_file accepts custom message"
    (Printf.sprintf {|assert_non_empty_file("%s", "artifact should not be empty")|} empty_file)
    {|Error(AssertionError: "Assertion failed: artifact should not be empty.")|};
  test "assert_non_empty_file rejects non-string path"
    {|assert_non_empty_file(1)|}
    {|Error(TypeError: "Function `assert_non_empty_file` expects a String as its first argument, got Int.")|};
  (try Sys.remove existing_file with Sys_error _ -> ());
  (try Sys.remove empty_file with Sys_error _ -> ());
  (try Unix.rmdir temp_dir with Unix.Unix_error _ -> ());
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
