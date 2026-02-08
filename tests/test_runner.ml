(* tests/test_runner.ml *)
(* Test runner for T language Phase 0 + Phase 1 + Phase 2 + Phase 3 + Phase 4 + Phase 5 + Phase 6 *)

let pass_count = ref 0
let fail_count = ref 0

(** Evaluate a string and return the result, using a shared environment across statements *)
let eval_string input =
  let env = Eval.initial_env () in
  let lexbuf = Lexing.from_string input in
  let program = Parser.program Lexer.token lexbuf in
  let (result, _env) = Eval.eval_program program env in
  result

(** Evaluate a string and return (result, env) for multi-step tests *)
let eval_string_env input env =
  let lexbuf = Lexing.from_string input in
  let program = Parser.program Lexer.token lexbuf in
  Eval.eval_program program env

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
  Printf.printf "\n=== T Language Phase 0 + Phase 1 + Phase 2 + Phase 3 + Phase 4 + Phase 5 + Phase 6 Tests ===\n\n";

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

  (* ============================================ *)
  (* --- Phase 2: Tabular Data and Arrow Integration --- *)
  (* ============================================ *)

  (* Create test CSV file for Phase 2 tests *)
  let csv_path = "test_phase2.csv" in
  let oc = open_out csv_path in
  output_string oc "name,age,score\nAlice,30,95.5\nBob,25,87.3\nCharlie,35,92.1\n";
  close_out oc;

  let csv_path_types = "test_phase2_types.csv" in
  let oc2 = open_out csv_path_types in
  output_string oc2 "id,active,value\n1,true,3.14\n2,false,2.71\n3,true,1.41\n";
  close_out oc2;

  let csv_path_na = "test_phase2_na.csv" in
  let oc3 = open_out csv_path_na in
  output_string oc3 "x,y\n1,hello\nNA,world\n3,NA\n";
  close_out oc3;

  let csv_path_empty = "test_phase2_empty.csv" in
  let oc4 = open_out csv_path_empty in
  output_string oc4 "a,b,c\n";
  close_out oc4;

  Printf.printf "Phase 2 — read_csv():\n";
  (* Use shared env for multi-step DataFrame tests *)
  let env = Eval.initial_env () in
  let (_, env) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_path) env in
  let (v, _) = eval_string_env "type(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = {|"DataFrame"|} then begin
    incr pass_count; Printf.printf "  ✓ read_csv returns DataFrame\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ read_csv returns DataFrame\n    Expected: \"DataFrame\"\n    Got: %s\n" result
  end;

  test "read_csv with missing file"
    {|read_csv("nonexistent_file.csv")|}
    {|Error(FileError: "File Error: nonexistent_file.csv: No such file or directory")|};
  test "read_csv with non-string arg"
    "read_csv(42)"
    {|Error(TypeError: "read_csv() expects a String path")|};
  test "read_csv with NA arg"
    "read_csv(NA)"
    {|Error(TypeError: "read_csv() expects a String path, got NA")|};
  print_newline ();

  Printf.printf "Phase 2 — nrow() and ncol():\n";
  let (v, _) = eval_string_env "nrow(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ nrow returns correct count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ nrow returns correct count\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "ncol(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ ncol returns correct count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ ncol returns correct count\n    Expected: 3\n    Got: %s\n" result
  end;

  test "nrow on non-DataFrame"
    "nrow(42)"
    {|Error(TypeError: "nrow() expects a DataFrame")|};
  test "ncol on non-DataFrame"
    "ncol([1, 2, 3])"
    {|Error(TypeError: "ncol() expects a DataFrame")|};
  test "nrow on NA"
    "nrow(NA)"
    {|Error(TypeError: "nrow() expects a DataFrame, got NA")|};
  print_newline ();

  Printf.printf "Phase 2 — colnames():\n";
  let (v, _) = eval_string_env "colnames(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  ✓ colnames returns column names\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ colnames returns column names\n    Expected: [\"name\", \"age\", \"score\"]\n    Got: %s\n" result
  end;

  test "colnames on non-DataFrame"
    {|colnames("hello")|}
    {|Error(TypeError: "colnames() expects a DataFrame")|};
  print_newline ();

  Printf.printf "Phase 2 — Column Access (dot notation):\n";
  let (v, _) = eval_string_env "df.name" env in
  let result = Ast.Utils.value_to_string v in
  if result = {|Vector["Alice", "Bob", "Charlie"]|} then begin
    incr pass_count; Printf.printf "  ✓ column access by name returns Vector\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ column access by name returns Vector\n    Expected: Vector[\"Alice\", \"Bob\", \"Charlie\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "df.age" env in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[30, 25, 35]" then begin
    incr pass_count; Printf.printf "  ✓ numeric column access returns typed values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ numeric column access returns typed values\n    Expected: Vector[30, 25, 35]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "df.score" env in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[95.5, 87.3, 92.1]" then begin
    incr pass_count; Printf.printf "  ✓ float column access returns typed values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ float column access returns typed values\n    Expected: Vector[95.5, 87.3, 92.1]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "df.nonexistent" env in
  let result = Ast.Utils.value_to_string v in
  if result = {|Error(KeyError: "column 'nonexistent' not found in DataFrame")|} then begin
    incr pass_count; Printf.printf "  ✓ missing column returns error\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ missing column returns error\n    Expected: Error(KeyError: ...)\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — DataFrame Type Inference:\n";
  let (_, env2) = eval_string_env (Printf.sprintf {|df2 = read_csv("%s")|} csv_path_types) env in
  let (v, _) = eval_string_env "df2.id" env2 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 2, 3]" then begin
    incr pass_count; Printf.printf "  ✓ integer columns inferred correctly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ integer columns inferred correctly\n    Expected: Vector[1, 2, 3]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "df2.active" env2 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[true, false, true]" then begin
    incr pass_count; Printf.printf "  ✓ boolean columns inferred correctly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ boolean columns inferred correctly\n    Expected: Vector[true, false, true]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "df2.value" env2 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[3.14, 2.71, 1.41]" then begin
    incr pass_count; Printf.printf "  ✓ float columns inferred correctly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ float columns inferred correctly\n    Expected: Vector[3.14, 2.71, 1.41]\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — NA in CSV:\n";
  let (_, env3) = eval_string_env (Printf.sprintf {|df3 = read_csv("%s")|} csv_path_na) env in
  let (v, _) = eval_string_env "df3.x" env3 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, NA, 3]" then begin
    incr pass_count; Printf.printf "  ✓ NA values preserved in CSV import\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ NA values preserved in CSV import\n    Expected: Vector[1, NA, 3]\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — Empty DataFrame:\n";
  let (_, env4) = eval_string_env (Printf.sprintf {|df4 = read_csv("%s")|} csv_path_empty) env in
  let (v, _) = eval_string_env "nrow(df4)" env4 in
  let result = Ast.Utils.value_to_string v in
  if result = "0" then begin
    incr pass_count; Printf.printf "  ✓ empty CSV has 0 rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ empty CSV has 0 rows\n    Expected: 0\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "ncol(df4)" env4 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ empty CSV retains column count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ empty CSV retains column count\n    Expected: 3\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — DataFrame in Pipelines:\n";
  let (v, _) = eval_string_env (Printf.sprintf {|read_csv("%s") |> nrow|} csv_path) env in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ DataFrame works as pipeline input (nrow)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ DataFrame works as pipeline input (nrow)\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env (Printf.sprintf {|read_csv("%s") |> colnames|} csv_path) env in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "age", "score"]|} then begin
    incr pass_count; Printf.printf "  ✓ DataFrame works as pipeline input (colnames)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ DataFrame works as pipeline input (colnames)\n    Expected: [\"name\", \"age\", \"score\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env (Printf.sprintf {|read_csv("%s") |> ncol|} csv_path) env in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ DataFrame works as pipeline input (ncol)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ DataFrame works as pipeline input (ncol)\n    Expected: 3\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — DataFrame Display:\n";
  let (v, _) = eval_string_env "df" env in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(3 rows x 3 cols: [name, age, score])" then begin
    incr pass_count; Printf.printf "  ✓ DataFrame display format correct\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ DataFrame display format correct\n    Expected: DataFrame(3 rows x 3 cols: [name, age, score])\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 2 — Immutability:\n";
  test "type of DataFrame"
    (Printf.sprintf {|type(read_csv("%s"))|} csv_path)
    {|"DataFrame"|};
  print_newline ();

  (* Clean up test CSV files *)
  (try Sys.remove csv_path with _ -> ());
  (try Sys.remove csv_path_types with _ -> ());
  (try Sys.remove csv_path_na with _ -> ());
  (try Sys.remove csv_path_empty with _ -> ());

  (* ============================================ *)
  (* --- Phase 3: Pipelines and Execution Graph --- *)
  (* ============================================ *)

  Printf.printf "Phase 3 — Basic Pipeline:\n";
  test "simple pipeline"
    "pipeline {\n  x = 1\n  y = 2\n  z = x + y\n}"
    "Pipeline(3 nodes: [x, y, z])";
  test "pipeline type"
    "type(pipeline {\n  a = 10\n})"
    {|"Pipeline"|};
  test "pipeline with expressions"
    "pipeline {\n  a = 2 * 3\n  b = a + 4\n}"
    "Pipeline(2 nodes: [a, b])";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Node Access:\n";
  let env_p3 = Eval.initial_env () in
  let (_, env_p3) = eval_string_env "p = pipeline {\n  x = 10\n  y = 20\n  total = x + y\n}" env_p3 in
  let (v, _) = eval_string_env "p.x" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "10" then begin
    incr pass_count; Printf.printf "  ✓ pipeline node access via dot (x)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline node access via dot (x)\n    Expected: 10\n    Got: %s\n" result
  end;
  let (v, _) = eval_string_env "p.total" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "30" then begin
    incr pass_count; Printf.printf "  ✓ pipeline node access via dot (total)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline node access via dot (total)\n    Expected: 30\n    Got: %s\n" result
  end;
  let (v, _) = eval_string_env "p.nonexistent" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = {|Error(KeyError: "node 'nonexistent' not found in Pipeline")|} then begin
    incr pass_count; Printf.printf "  ✓ missing pipeline node returns error\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ missing pipeline node returns error\n    Expected: Error(KeyError: ...)\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 3 — Deterministic Execution:\n";
  test "pipeline executes deterministically"
    "p1 = pipeline {\n  a = 5\n  b = a * 2\n  c = b + 1\n}; p2 = pipeline {\n  a = 5\n  b = a * 2\n  c = b + 1\n}; p1.c == p2.c"
    "true";
  print_newline ();

  Printf.printf "Phase 3 — Dependency Resolution:\n";
  test "out-of-order dependencies resolved"
    "p = pipeline {\n  result = x + y\n  x = 3\n  y = 7\n}; p.result"
    "10";
  test "chain dependencies"
    "p = pipeline {\n  a = 1\n  b = a + 1\n  c = b + 1\n  d = c + 1\n}; p.d"
    "4";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Introspection:\n";
  let (v, _) = eval_string_env "pipeline_nodes(p)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["x", "y", "total"]|} then begin
    incr pass_count; Printf.printf "  ✓ pipeline_nodes() lists all nodes\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_nodes() lists all nodes\n    Expected: [\"x\", \"y\", \"total\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|pipeline_node(p, "total")|} env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "30" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_node() gets specific node value\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_node() gets specific node value\n    Expected: 30\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "pipeline_deps(p)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`x`: [], `y`: [], `total`: ["x", "y"]}|} then begin
    incr pass_count; Printf.printf "  ✓ pipeline_deps() returns dependency graph\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_deps() returns dependency graph\n    Expected: {`x`: [], `y`: [], `total`: [\"x\", \"y\"]}\n    Got: %s\n" result
  end;

  test "pipeline_nodes on non-pipeline"
    "pipeline_nodes(42)"
    {|Error(TypeError: "pipeline_nodes() expects a Pipeline")|};
  test "pipeline_node missing key"
    {|p = pipeline { a = 1 }; pipeline_node(p, "b")|}
    {|Error(KeyError: "node 'b' not found in Pipeline")|};
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Re-run (Caching):\n";
  let (v, _) = eval_string_env "pipeline_run(p)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "Pipeline(3 nodes: [x, y, total])" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_run() re-runs and returns same result\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_run() re-runs and returns same result\n    Expected: Pipeline(3 nodes: [x, y, total])\n    Got: %s\n" result
  end;

  (* Re-run produces same node values *)
  let (rerun_result, _) = eval_string_env "p2 = pipeline_run(p); p2.total" env_p3 in
  let result = Ast.Utils.value_to_string rerun_result in
  if result = "30" then begin
    incr pass_count; Printf.printf "  ✓ re-run preserves cached values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ re-run preserves cached values\n    Expected: 30\n    Got: %s\n" result
  end;

  test "pipeline_run on non-pipeline"
    "pipeline_run(42)"
    {|Error(TypeError: "pipeline_run() expects a Pipeline")|};
  print_newline ();

  Printf.printf "Phase 3 — Pipeline with Pipes:\n";
  test "pipeline with pipe operator"
    "double = \\(x) x * 2\np = pipeline {\n  a = 5\n  b = a |> double\n}; p.b"
    "10";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline with Functions:\n";
  test "pipeline with function calls"
    "p = pipeline {\n  data = [1, 2, 3]\n  total = sum(data)\n  count = length(data)\n}; p.total"
    "6";
  test "pipeline nodes available individually"
    "p = pipeline {\n  data = [1, 2, 3]\n  total = sum(data)\n  count = length(data)\n}; p.count"
    "3";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Error Handling:\n";
  test "pipeline cycle detection"
    "pipeline {\n  a = b\n  b = a\n}"
    {|Error(ValueError: "Pipeline has a dependency cycle involving node 'a'")|};
  test "pipeline with error in node"
    "pipeline {\n  a = 1 / 0\n  b = a + 1\n}"
    {|Error(ValueError: "Pipeline node 'a' failed: Error(DivisionByZero: "Division by zero")")|};
  print_newline ();

  Printf.printf "Phase 3 — Pipeline with DataFrame:\n";
  (* Create CSV for pipeline DataFrame tests *)
  let csv_p3 = "test_phase3.csv" in
  let oc5 = open_out csv_p3 in
  output_string oc5 "name,value\nAlice,10\nBob,20\nCharlie,30\n";
  close_out oc5;

  let (_, env_p3_df) = eval_string_env (Printf.sprintf
    {|p = pipeline {
  data = read_csv("%s")
  rows = data |> nrow
  cols = data |> ncol
  names = data |> colnames
}|} csv_p3) (Eval.initial_env ()) in
  let (v, _) = eval_string_env "p.rows" env_p3_df in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ pipeline with DataFrame nrow\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline with DataFrame nrow\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "p.cols" env_p3_df in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ pipeline with DataFrame ncol\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline with DataFrame ncol\n    Expected: 2\n    Got: %s\n" result
  end;
  (try Sys.remove csv_p3 with _ -> ());
  print_newline ();

  (* ============================================ *)
  (* --- Phase 4: Core Data Verbs (colcraft) --- *)
  (* ============================================ *)

  (* Create test CSV for Phase 4 tests *)
  let csv_p4 = "test_phase4.csv" in
  let oc6 = open_out csv_p4 in
  output_string oc6 "name,age,score,dept\nAlice,30,95.5,eng\nBob,25,87.3,sales\nCharlie,35,92.1,eng\nDiana,28,88.0,sales\nEve,32,91.5,eng\n";
  close_out oc6;

  let env_p4 = Eval.initial_env () in
  let (_, env_p4) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_p4) env_p4 in

  Printf.printf "Phase 4 — select():\n";
  let (v, _) = eval_string_env {|select(df, "name", "age")|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 2 cols: [name, age])" then begin
    incr pass_count; Printf.printf "  ✓ select two columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ select two columns\n    Expected: DataFrame(5 rows x 2 cols: [name, age])\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|select(df, "name")|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 1 cols: [name])" then begin
    incr pass_count; Printf.printf "  ✓ select single column\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ select single column\n    Expected: DataFrame(5 rows x 1 cols: [name])\n    Got: %s\n" result
  end;

  test "select missing column"
    (Printf.sprintf {|df = read_csv("%s"); select(df, "nonexistent")|} csv_p4)
    {|Error(KeyError: "Column(s) not found: nonexistent")|};
  test "select non-string arg"
    (Printf.sprintf {|df = read_csv("%s"); select(df, 42)|} csv_p4)
    {|Error(TypeError: "select() expects string column names")|};
  test "select non-dataframe"
    {|select(42, "name")|}
    {|Error(TypeError: "select() expects a DataFrame as first argument")|};
  test "select with pipe"
    (Printf.sprintf {|df = read_csv("%s"); df |> select("name", "score") |> ncol|} csv_p4)
    "2";
  print_newline ();

  Printf.printf "Phase 4 — filter():\n";
  let (v, _) = eval_string_env {|filter(df, \(row) row.age > 28)|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(3 rows x 4 cols: [name, age, score, dept])" then begin
    incr pass_count; Printf.printf "  ✓ filter by age > 28\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ filter by age > 28\n    Expected: DataFrame(3 rows x 4 cols: [name, age, score, dept])\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|df |> filter(\(row) row.dept == "eng") |> nrow|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ filter by dept == eng via pipe\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ filter by dept == eng via pipe\n    Expected: 3\n    Got: %s\n" result
  end;

  test "filter non-dataframe"
    {|filter(42, \(x) true)|}
    {|Error(TypeError: "filter() expects a DataFrame as first argument")|};
  print_newline ();

  Printf.printf "Phase 4 — mutate():\n";
  let (v, _) = eval_string_env {|mutate(df, "age_plus_10", \(row) row.age + 10)|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 5 cols: [name, age, score, dept, age_plus_10])" then begin
    incr pass_count; Printf.printf "  ✓ mutate adds new column\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ mutate adds new column\n    Expected: DataFrame(5 rows x 5 cols: [name, age, score, dept, age_plus_10])\n    Got: %s\n" result
  end;

  (* mutate replaces existing column *)
  let (v, _) = eval_string_env {|mutate(df, "age", \(row) row.age + 1) |> ncol|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "4" then begin
    incr pass_count; Printf.printf "  ✓ mutate replaces existing column (same col count)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ mutate replaces existing column (same col count)\n    Expected: 4\n    Got: %s\n" result
  end;

  test "mutate non-dataframe"
    {|mutate(42, "x", \(r) r)|}
    {|Error(TypeError: "mutate() expects a DataFrame as first argument")|};
  test "mutate non-string col name"
    (Printf.sprintf {|df = read_csv("%s"); mutate(df, 42, \(r) r)|} csv_p4)
    {|Error(TypeError: "mutate() expects a string column name as second argument")|};
  print_newline ();

  Printf.printf "Phase 4 — arrange():\n";
  (* Sort by age ascending — check first row name *)
  let (v, _) = eval_string_env {|df2 = arrange(df, "age"); select(df2, "name") |> \(d) d.name|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = {|Vector["Bob", "Diana", "Alice", "Eve", "Charlie"]|} then begin
    incr pass_count; Printf.printf "  ✓ arrange ascending by age\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ arrange ascending by age\n    Expected: Vector[\"Bob\", \"Diana\", \"Alice\", \"Eve\", \"Charlie\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|df2 = arrange(df, "age", "desc"); select(df2, "name") |> \(d) d.name|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = {|Vector["Charlie", "Eve", "Alice", "Diana", "Bob"]|} then begin
    incr pass_count; Printf.printf "  ✓ arrange descending by age\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ arrange descending by age\n    Expected: Vector[\"Charlie\", \"Eve\", \"Alice\", \"Diana\", \"Bob\"]\n    Got: %s\n" result
  end;

  test "arrange missing column"
    (Printf.sprintf {|df = read_csv("%s"); arrange(df, "nonexistent")|} csv_p4)
    {|Error(KeyError: "Column 'nonexistent' not found in DataFrame")|};
  test "arrange invalid direction"
    (Printf.sprintf {|df = read_csv("%s"); arrange(df, "age", "up")|} csv_p4)
    {|Error(ValueError: "arrange() direction must be "asc" or "desc", got "up"")|};

  print_newline ();

  Printf.printf "Phase 4 — group_by():\n";
  let (v, _) = eval_string_env {|group_by(df, "dept")|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(5 rows x 4 cols: [name, age, score, dept]) grouped by [dept]" then begin
    incr pass_count; Printf.printf "  ✓ group_by marks grouping\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ group_by marks grouping\n    Expected: DataFrame(5 rows x 4 cols: [name, age, score, dept]) grouped by [dept]\n    Got: %s\n" result
  end;

  test "group_by missing column"
    (Printf.sprintf {|df = read_csv("%s"); group_by(df, "nonexistent")|} csv_p4)
    {|Error(KeyError: "Column(s) not found: nonexistent")|};
  test "group_by non-string"
    (Printf.sprintf {|df = read_csv("%s"); group_by(df, 42)|} csv_p4)
    {|Error(TypeError: "group_by() expects string column names")|};
  test "group_by no columns"
    (Printf.sprintf {|df = read_csv("%s"); group_by(df)|} csv_p4)
    {|Error(ArityError: "group_by() requires at least one column name")|};
  print_newline ();

  Printf.printf "Phase 4 — summarize():\n";
  (* Ungrouped summarize *)
  let (v, _) = eval_string_env {|summarize(df, "total_rows", \(d) nrow(d))|} env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(1 rows x 1 cols: [total_rows])" then begin
    incr pass_count; Printf.printf "  ✓ ungrouped summarize produces 1-row result\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ ungrouped summarize produces 1-row result\n    Expected: DataFrame(1 rows x 1 cols: [total_rows])\n    Got: %s\n" result
  end;

  (* Grouped summarize *)
  let (v, _) = eval_string_env
    {|df |> group_by("dept") |> summarize("count", \(g) nrow(g))|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "DataFrame(2 rows x 2 cols: [dept, count])" then begin
    incr pass_count; Printf.printf "  ✓ grouped summarize produces per-group result\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped summarize produces per-group result\n    Expected: DataFrame(2 rows x 2 cols: [dept, count])\n    Got: %s\n" result
  end;

  (* Check grouped summarize values *)
  let (v, _) = eval_string_env
    {|result = df |> group_by("dept") |> summarize("count", \(g) nrow(g)); result.count|}
    env_p4 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[3, 2]" then begin
    incr pass_count; Printf.printf "  ✓ grouped summarize correct counts (eng=3, sales=2)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ grouped summarize correct counts (eng=3, sales=2)\n    Expected: Vector[3, 2]\n    Got: %s\n" result
  end;

  test "summarize non-dataframe"
    {|summarize(42, "x", \(d) d)|}
    {|Error(TypeError: "summarize() expects a DataFrame as first argument")|};
  print_newline ();

  Printf.printf "Phase 4 — Pipeline Integration:\n";
  test "tidy-style pipeline"
    (Printf.sprintf
      {|df = read_csv("%s")
df |> filter(\(row) row.age > 25)
  |> select("name", "score")
  |> arrange("score", "desc")
  |> nrow|} csv_p4)
    "4";
  test "mutate + filter pipeline"
    (Printf.sprintf
      {|df = read_csv("%s")
df |> mutate("senior", \(row) row.age >= 30)
  |> filter(\(row) row.senior == true)
  |> nrow|} csv_p4)
    "3";
  print_newline ();

  (* Clean up Phase 4 CSV *)
  (try Sys.remove csv_p4 with _ -> ());

  (* ============================================ *)
  (* --- Phase 5: Numerical and Statistical Libraries --- *)
  (* ============================================ *)

  Printf.printf "Phase 5 — Math: sqrt():\n";
  test "sqrt of integer" "sqrt(4)" "2.";
  test "sqrt of float" "sqrt(2.0)" "1.41421356237";
  test "sqrt of 0" "sqrt(0)" "0.";
  test "sqrt negative" "sqrt(-1)" {|Error(ValueError: "sqrt() is undefined for negative numbers")|};
  test "sqrt NA" "sqrt(NA)" {|Error(TypeError: "sqrt() encountered NA value. Handle missingness explicitly.")|};
  test "sqrt non-numeric" {|sqrt("hello")|} {|Error(TypeError: "sqrt() expects a number or numeric Vector")|};
  print_newline ();

  Printf.printf "Phase 5 — Math: abs():\n";
  test "abs of positive int" "abs(5)" "5";
  test "abs of negative int" "abs(0 - 5)" "5";
  test "abs of negative float" "abs(0.0 - 3.14)" "3.14";
  test "abs of zero" "abs(0)" "0";
  test "abs NA" "abs(NA)" {|Error(TypeError: "abs() encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Math: log():\n";
  test "log of 1" "log(1)" "0.";
  test "log of positive float" "log(10)" "2.30258509299";
  test "log of 0" "log(0)" {|Error(ValueError: "log() is undefined for non-positive numbers")|};
  test "log of negative" "log(0 - 1)" {|Error(ValueError: "log() is undefined for non-positive numbers")|};
  test "log NA" "log(NA)" {|Error(TypeError: "log() encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Math: exp():\n";
  test "exp of 0" "exp(0)" "1.";
  test "exp of 1" "exp(1)" "2.71828182846";
  test "exp NA" "exp(NA)" {|Error(TypeError: "exp() encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Math: pow():\n";
  test "pow integer" "pow(2, 3)" "8.";
  test "pow float base" "pow(4.0, 0.5)" "2.";
  test "pow zero exponent" "pow(5, 0)" "1.";
  test "pow NA base" "pow(NA, 2)" {|Error(TypeError: "pow() encountered NA value. Handle missingness explicitly.")|};
  test "pow NA exponent" "pow(2, NA)" {|Error(TypeError: "pow() encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Math: Vector operations:\n";
  (* Create a CSV for vector tests *)
  let csv_p5_vec = "test_phase5_vec.csv" in
  let oc_vec = open_out csv_p5_vec in
  output_string oc_vec "a,b,c\n1,2,-1\n4,3,2\n9,4,-3\n";
  close_out oc_vec;
  let env_p5 = Eval.initial_env () in
  let (_, env_p5) = eval_string_env (Printf.sprintf {|vdf = read_csv("%s")|} csv_p5_vec) env_p5 in

  let (v, _) = eval_string_env "sqrt(vdf.a)" env_p5 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1., 2., 3.]" then begin
    incr pass_count; Printf.printf "  ✓ sqrt on vector\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ sqrt on vector\n    Expected: Vector[1., 2., 3.]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "abs(vdf.c)" env_p5 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[1, 2, 3]" then begin
    incr pass_count; Printf.printf "  ✓ abs on vector\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ abs on vector\n    Expected: Vector[1, 2, 3]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "pow(vdf.b, 2)" env_p5 in
  let result = Ast.Utils.value_to_string v in
  if result = "Vector[4., 9., 16.]" then begin
    incr pass_count; Printf.printf "  ✓ pow on vector\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pow on vector\n    Expected: Vector[4., 9., 16.]\n    Got: %s\n" result
  end;
  (try Sys.remove csv_p5_vec with _ -> ());
  print_newline ();

  Printf.printf "Phase 5 — Math: Pipeline integration:\n";
  test "sqrt in pipe" "4 |> sqrt" "2.";
  test "exp and log roundtrip" "log(exp(1.0))" "1.";
  test "chained math" "pow(2, 10) |> sqrt" "32.";
  print_newline ();

  Printf.printf "Phase 5 — Stats: mean():\n";
  test "mean of int list" "mean([1, 2, 3, 4, 5])" "3.";
  test "mean of float list" "mean([1.0, 2.0, 3.0])" "2.";
  test "mean empty" "mean([])" {|Error(ValueError: "mean() called on empty list")|};
  test "mean with NA" "mean([1, NA, 3])" {|Error(TypeError: "mean() encountered NA value. Handle missingness explicitly.")|};
  test "mean non-numeric" {|mean("hello")|} {|Error(TypeError: "mean() expects a numeric List or Vector")|};
  print_newline ();

  Printf.printf "Phase 5 — Stats: sd():\n";
  test "sd of list" "sd([2, 4, 4, 4, 5, 5, 7, 9])" "2.1380899353";
  test "sd single value" "sd([42])" {|Error(ValueError: "sd() requires at least 2 values")|};
  test "sd with NA" "sd([1, NA, 3])" {|Error(TypeError: "sd() encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Stats: quantile():\n";
  test "quantile median" "quantile([1, 2, 3, 4, 5], 0.5)" "3.";
  test "quantile min" "quantile([1, 2, 3, 4, 5], 0.0)" "1.";
  test "quantile max" "quantile([1, 2, 3, 4, 5], 1.0)" "5.";
  test "quantile Q1" "quantile([1, 2, 3, 4, 5], 0.25)" "2.";
  test "quantile invalid p" "quantile([1, 2, 3], 1.5)" {|Error(ValueError: "quantile() expects a probability between 0 and 1")|};
  test "quantile empty" "quantile([], 0.5)" {|Error(ValueError: "quantile() called on empty data")|};
  print_newline ();

  Printf.printf "Phase 5 — Stats: cor():\n";
  (* Create CSV for correlation tests *)
  let csv_p5_cor = "test_phase5_cor.csv" in
  let oc_cor = open_out csv_p5_cor in
  output_string oc_cor "x,y,z,w\n1,2,6,1\n2,4,4,1\n3,6,2,1\n";
  close_out oc_cor;
  let env_cor = Eval.initial_env () in
  let (_, env_cor) = eval_string_env (Printf.sprintf {|cdf = read_csv("%s")|} csv_p5_cor) env_cor in

  let (v, _) = eval_string_env "cor(cdf.x, cdf.y)" env_cor in
  let result = Ast.Utils.value_to_string v in
  if result = "1." then begin
    incr pass_count; Printf.printf "  ✓ perfect positive correlation\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ perfect positive correlation\n    Expected: 1.\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "cor(cdf.x, cdf.z)" env_cor in
  let result = Ast.Utils.value_to_string v in
  if result = "-1." then begin
    incr pass_count; Printf.printf "  ✓ perfect negative correlation\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ perfect negative correlation\n    Expected: -1.\n    Got: %s\n" result
  end;

  test "cor non-numeric"
    {|cor("hello", "world")|}
    {|Error(TypeError: "cor() expects two numeric Vectors or Lists")|};
  test "cor with NA"
    "cor(NA, [1, 2, 3])"
    {|Error(TypeError: "cor() encountered NA value. Handle missingness explicitly.")|};

  (try Sys.remove csv_p5_cor with _ -> ());
  print_newline ();

  Printf.printf "Phase 5 — Stats: lm():\n";
  (* Create test CSV for lm() *)
  let csv_p5_lm = "test_phase5_lm.csv" in
  let oc_lm = open_out csv_p5_lm in
  output_string oc_lm "x,y\n1,2\n2,4\n3,6\n4,8\n5,10\n";
  close_out oc_lm;

  let env_lm = Eval.initial_env () in
  let (_, env_lm) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_p5_lm) env_lm in
  let (_, env_lm) = eval_string_env {|model = lm(df, "y", "x")|} env_lm in

  let (v, _) = eval_string_env "type(model)" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = {|"Dict"|} then begin
    incr pass_count; Printf.printf "  ✓ lm() returns a Dict\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() returns a Dict\n    Expected: \"Dict\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "model.slope" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "2." then begin
    incr pass_count; Printf.printf "  ✓ lm() correct slope (2.0)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() correct slope (2.0)\n    Expected: 2.\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "model.intercept" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "0." then begin
    incr pass_count; Printf.printf "  ✓ lm() correct intercept (0.0)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() correct intercept (0.0)\n    Expected: 0.\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "model.r_squared" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "1." then begin
    incr pass_count; Printf.printf "  ✓ lm() perfect R-squared (1.0)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() perfect R-squared (1.0)\n    Expected: 1.\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "model.n" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "5" then begin
    incr pass_count; Printf.printf "  ✓ lm() correct observation count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() correct observation count\n    Expected: 5\n    Got: %s\n" result
  end;

  test "lm missing column"
    (Printf.sprintf {|df = read_csv("%s"); lm(df, "y", "z")|} csv_p5_lm)
    {|Error(KeyError: "Column 'z' not found in DataFrame")|};
  test "lm non-dataframe"
    {|lm(42, "y", "x")|}
    {|Error(TypeError: "lm() expects a DataFrame as first argument")|};
  test "lm non-string col"
    (Printf.sprintf {|df = read_csv("%s"); lm(df, 42, "x")|} csv_p5_lm)
    {|Error(TypeError: "lm() expects string column names")|};
  print_newline ();

  Printf.printf "Phase 5 — Stats: Pipeline integration:\n";
  test "mean in pipe"
    "[1, 2, 3, 4, 5] |> mean"
    "3.";
  test "sd in pipe"
    "[2, 4, 4, 4, 5, 5, 7, 9] |> sd"
    "2.1380899353";
  print_newline ();

  Printf.printf "Phase 5 — Functions available without imports:\n";
  test "sqrt available" "type(sqrt(4))" {|"Float"|};
  test "abs available" "type(abs(0 - 5))" {|"Int"|};
  test "log available" "type(log(1))" {|"Float"|};
  test "exp available" "type(exp(0))" {|"Float"|};
  test "pow available" "type(pow(2, 3))" {|"Float"|};
  test "mean available" "type(mean([1, 2]))" {|"Float"|};
  test "sd available" "type(sd([1, 2, 3]))" {|"Float"|};
  test "quantile available" "type(quantile([1, 2, 3], 0.5))" {|"Float"|};
  test "cor available" "type(cor([1, 2, 3], [4, 5, 6]))" {|"Float"|};
  print_newline ();

  (* Clean up Phase 5 CSV *)
  (try Sys.remove csv_p5_lm with _ -> ());

  (* ============================================ *)
  (* --- Phase 6: Intent Blocks and Tooling Hooks --- *)
  (* ============================================ *)

  Printf.printf "Phase 6 — Intent Blocks:\n";
  test "intent block creation"
    {|intent { description: "Load data", assumes: "File exists" }|}
    {|Intent{description: "Load data", assumes: "File exists"}|};
  test "intent type"
    {|type(intent { description: "test" })|}
    {|"Intent"|};
  test "intent block assignment"
    {|i = intent { goal: "compute mean" }; type(i)|}
    {|"Intent"|};
  test "intent block with expression values"
    {|x = "dynamic"; intent { note: x }|}
    {|Intent{note: "dynamic"}|};
  print_newline ();

  Printf.printf "Phase 6 — Intent Fields:\n";
  test "intent_fields returns Dict"
    {|i = intent { description: "test", version: "1.0" }; type(intent_fields(i))|}
    {|"Dict"|};
  test "intent_fields values"
    {|i = intent { a: "hello", b: "world" }; intent_fields(i)|}
    {|{`a`: "hello", `b`: "world"}|};
  test "intent_fields on non-intent"
    "intent_fields(42)"
    {|Error(TypeError: "intent_fields() expects an Intent value")|};
  print_newline ();

  Printf.printf "Phase 6 — Intent Get:\n";
  test "intent_get specific field"
    {|i = intent { description: "test", author: "T" }; intent_get(i, "description")|}
    {|"test"|};
  test "intent_get missing field"
    {|i = intent { a: "1" }; intent_get(i, "b")|}
    {|Error(KeyError: "Intent field 'b' not found")|};
  test "intent_get on non-intent"
    {|intent_get(42, "x")|}
    {|Error(TypeError: "intent_get() expects an Intent value as first argument")|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Scalars:\n";
  test "explain integer kind"
    {|e = explain(42); e.kind|}
    {|"value"|};
  test "explain integer type"
    {|e = explain(42); e.type|}
    {|"Int"|};
  test "explain string"
    {|e = explain("hello"); e.type|}
    {|"String"|};
  test "explain bool"
    {|e = explain(true); e.type|}
    {|"Bool"|};
  test "explain float"
    {|e = explain(3.14); e.type|}
    {|"Float"|};
  test "explain null"
    {|e = explain(null); e.type|}
    {|"Null"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: NA:\n";
  test "explain NA kind"
    {|e = explain(NA); e.kind|}
    {|"value"|};
  test "explain NA type"
    {|e = explain(NA); e.type|}
    {|"NA"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Vectors:\n";
  test "explain vector kind"
    {|v = [1, 2, 3]; e = explain(v); e.kind|}
    {|"value"|};
  test "explain vector type"
    {|v = [1, 2, 3]; e = explain(v); e.type|}
    {|"List"|};
  test "explain vector length"
    {|v = [1, 2, 3]; e = explain(v); e.length|}
    "3";
  test "explain vector na_count"
    {|v = [1, NA, 3]; e = explain(v); e.na_count|}
    "1";
  print_newline ();

  Printf.printf "Phase 6 — Explain: DataFrame:\n";
  (* Create test CSV for explain tests *)
  let csv_p6 = "test_phase6.csv" in
  let oc7 = open_out csv_p6 in
  output_string oc7 "name,age,score\nAlice,30,95.5\nBob,NA,87.3\nCharlie,35,NA\n";
  close_out oc7;

  let env_p6 = Eval.initial_env () in
  let (_, env_p6) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_p6) env_p6 in
  let (v, _) = eval_string_env "e = explain(df); e.kind" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = {|"dataframe"|} then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame kind\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame kind\n    Expected: \"dataframe\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); e.nrow" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame nrow\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame nrow\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); e.ncol" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame ncol\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame ncol\n    Expected: 3\n    Got: %s\n" result
  end;

  (* Check NA stats *)
  let (v, _) = eval_string_env "e = explain(df); e.na_stats.age" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "1" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame NA stats (age has 1 NA)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame NA stats (age has 1 NA)\n    Expected: 1\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); e.na_stats.score" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "1" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame NA stats (score has 1 NA)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame NA stats (score has 1 NA)\n    Expected: 1\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); e.na_stats.name" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "0" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame NA stats (name has 0 NAs)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame NA stats (name has 0 NAs)\n    Expected: 0\n    Got: %s\n" result
  end;

  (* Check schema *)
  let (v, _) = eval_string_env "e = explain(df); type(e.schema)" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = {|"List"|} then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame schema is a List\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame schema is a List\n    Expected: \"List\"\n    Got: %s\n" result
  end;

  (* Check example rows *)
  let (v, _) = eval_string_env "e = explain(df); type(e.example_rows)" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = {|"List"|} then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame example_rows is a List\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame example_rows is a List\n    Expected: \"List\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(df); length(e.example_rows)" env_p6 in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ explain DataFrame example_rows length (3 rows)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain DataFrame example_rows length (3 rows)\n    Expected: 3\n    Got: %s\n" result
  end;
  (try Sys.remove csv_p6 with _ -> ());
  print_newline ();

  Printf.printf "Phase 6 — Explain: Pipeline:\n";
  let (_, env_p6_pipe) = eval_string_env "p = pipeline {\n  x = 10\n  y = x + 5\n  z = y * 2\n}" (Eval.initial_env ()) in
  let (v, _) = eval_string_env "e = explain(p); e.kind" env_p6_pipe in
  let result = Ast.Utils.value_to_string v in
  if result = {|"pipeline"|} then begin
    incr pass_count; Printf.printf "  ✓ explain Pipeline kind\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain Pipeline kind\n    Expected: \"pipeline\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "e = explain(p); e.node_count" env_p6_pipe in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ explain Pipeline node_count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ explain Pipeline node_count\n    Expected: 3\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 6 — Explain: Intent:\n";
  test "explain intent kind"
    {|i = intent { description: "test" }; e = explain(i); e.kind|}
    {|"intent"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Error:\n";
  test "explain error"
    {|e = explain(1 / 0); e.type|}
    {|"Error"|};
  test "explain error code"
    {|e = explain(1 / 0); e.error_code|}
    {|"DivisionByZero"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Arity:\n";
  test "explain no args"
    "explain()"
    {|Error(ArityError: "Expected 1 arguments but got 0")|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Pipeline Integration:\n";
  test "explain in pipe"
    {|42 |> explain|}
    {|{`kind`: "value", `type`: "Int", `value`: 42}|};
  print_newline ();

  Printf.printf "Phase 6 — Functions available without imports:\n";
  test "explain available" {|type(explain(42))|}  {|"Dict"|};
  test "intent_fields available" {|i = intent { a: "1" }; type(intent_fields(i))|} {|"Dict"|};
  test "intent_get available" {|i = intent { a: "1" }; intent_get(i, "a")|} {|"1"|};
  print_newline ();

  (* --- Summary --- *)
  let total = !pass_count + !fail_count in
  Printf.printf "=== Results: %d/%d passed ===\n" !pass_count total;
  if !fail_count > 0 then begin
    Printf.printf "FAILED: %d tests failed\n" !fail_count;
    exit 1
  end else
    Printf.printf "All tests passed!\n"
