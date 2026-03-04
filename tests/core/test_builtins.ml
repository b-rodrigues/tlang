let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Builtins:\n";
  test "type of int" "type(42)" {|"Int"|};
  test "type of string" {|type("hello")|} {|"String"|};
  test "type of bool" "type(true)" {|"Bool"|};
  test "type of list" "type([1])" {|"List"|};
  test "assert true" "assert(true)" "true";
  test "assert false" "assert(false)" {|Error(AssertionError: "Assertion failed.")|};
  test "is_error on error" "is_error(1 / 0)" "true";
  test "is_error on value" "is_error(42)" "false";
  test "seq" "seq(1, 3)" "[1, 2, 3]";
  test "sum" "sum([1, 2, 3, 4, 5])" "15";
  test "map" "map([1, 2, 3], \\(x) x * x)" "[1, 4, 9]";
  print_newline ();

  Printf.printf "Filesystem Builtins:\n";
  test "getwd returns string" "type(getwd())" {|"String"|};
  test "file_exists false for /tmp (dir not file)" {|file_exists("/tmp")|} "false";
  test "file_exists false for nonexistent" {|file_exists("/nonexistent_abc_xyz_123")|} "false";
  test "file_exists wrong type" {|file_exists(42)|} {|Error(TypeError: "Function `file_exists` expects a String, got Int.")|};
  (* Create a temp file to test positive file_exists and read_file cases *)
  let tmp_file = Filename.temp_file "tlang_test_" ".txt" in
  let tmp_base = Filename.basename tmp_file in
  let tmp_dir = Filename.dirname tmp_file in
  test "file_exists true for regular file"
    (Printf.sprintf {|file_exists("%s")|} tmp_file) "true";
  test "read_file reads empty file"
    (Printf.sprintf {|read_file("%s")|} tmp_file) {|""|};
  test "list_files pattern exact match"
    (Printf.sprintf {|length(list_files("%s", pattern = "^%s$"))|} tmp_dir tmp_base)
    "1";
  test "list_files pattern no match"
    (Printf.sprintf {|length(list_files("%s", pattern = "^IMPOSSIBLE_MATCH_XYZ_9999$"))|} tmp_dir)
    "0";
  Sys.remove tmp_file;
  test "dir_exists true for /tmp" {|dir_exists("/tmp")|} "true";
  test "dir_exists false for nonexistent" {|dir_exists("/nonexistent_abc_xyz_123")|} "false";
  test "dir_exists wrong type" {|dir_exists(42)|} {|Error(TypeError: "Function `dir_exists` expects a String, got Int.")|};
  test "read_file nonexistent returns error" {|is_error(read_file("/nonexistent_abc_xyz_123"))|} "true";
  test "read_file wrong type" {|read_file(42)|} {|Error(TypeError: "Function `read_file` expects a String, got Int.")|};
  test "list_files default returns list" "type(list_files())" {|"List"|};
  test "list_files /tmp returns list" {|type(list_files("/tmp"))|} {|"List"|};
  test "list_files nonexistent returns error" {|is_error(list_files("/nonexistent_abc_xyz_123"))|} "true";
  test "list_files wrong type" {|list_files(42)|} {|Error(TypeError: "Function `list_files` expects a String path, got Int.")|};
  test "list_files extra positional arity error"
    {|list_files("/tmp", "/tmp")|}
    {|Error(ArityError: "Function `list_files` expects 1 arguments but received 2.")|};
  test "list_files pattern wrong type"
    {|list_files("/tmp", pattern = 42)|}
    {|Error(TypeError: "Argument `pattern` of `list_files` must be a String, got Int.")|};
  test "env HOME exists" {|type(env("HOME"))|} {|"String"|};
  test "env nonexistent returns null" {|env("NONEXISTENT_VAR_ABC_XYZ_123")|} "null";
  test "env wrong type" {|env(42)|} {|Error(TypeError: "Function `env` expects a String, got Int.")|};
  print_newline ();

  Printf.printf "Error Handling:\n";
  test "error propagation in addition" "(1 / 0) + 1" {|Error(DivisionByZero: "Division by zero.")|};
  test "error in list" "[1, 1/0, 3]" {|Error(DivisionByZero: "Division by zero.")|};
  print_newline ()
