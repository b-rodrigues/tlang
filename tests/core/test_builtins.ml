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
  test "dir_exists true for /tmp" {|dir_exists("/tmp")|} "true";
  test "dir_exists false for nonexistent" {|dir_exists("/nonexistent_abc_xyz_123")|} "false";
  test "dir_exists wrong type" {|dir_exists(42)|} {|Error(TypeError: "Function `dir_exists` expects a String, got Int.")|};
  test "read_file nonexistent returns error" {|is_error(read_file("/nonexistent_abc_xyz_123"))|} "true";
  test "read_file wrong type" {|read_file(42)|} {|Error(TypeError: "Function `read_file` expects a String, got Int.")|};
  test "list_files default returns list" "type(list_files())" {|"List"|};
  test "list_files /tmp returns list" {|type(list_files("/tmp"))|} {|"List"|};
  test "list_files nonexistent returns error" {|is_error(list_files("/nonexistent_abc_xyz_123"))|} "true";
  test "list_files wrong type" {|list_files(42)|} {|Error(TypeError: "Function `list_files` expects a String path, got Int.")|};
  test "env HOME exists" {|type(env("HOME"))|} {|"String"|};
  test "env nonexistent returns null" {|env("NONEXISTENT_VAR_ABC_XYZ_123")|} "null";
  test "env wrong type" {|env(42)|} {|Error(TypeError: "Function `env` expects a String, got Int.")|};
  print_newline ();

  Printf.printf "Error Handling:\n";
  test "error propagation in addition" "(1 / 0) + 1" {|Error(DivisionByZero: "Division by zero.")|};
  test "error in list" "[1, 1/0, 3]" {|Error(DivisionByZero: "Division by zero.")|};
  print_newline ()
