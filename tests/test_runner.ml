(* tests/test_runner.ml *)
(* Test runner for T language Phase 0 + Phase 1 + Phase 2 + Phase 3 *)

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
  Printf.printf "\n=== T Language Phase 0 + Phase 1 + Phase 2 + Phase 3 Tests ===\n\n";

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

  (* --- Summary --- *)
  let total = !pass_count + !fail_count in
  Printf.printf "=== Results: %d/%d passed ===\n" !pass_count total;
  if !fail_count > 0 then begin
    Printf.printf "FAILED: %d tests failed\n" !fail_count;
    exit 1
  end else
    Printf.printf "All tests passed!\n"
