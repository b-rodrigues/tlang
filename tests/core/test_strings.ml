(* tests/core/test_strings.ml *)

(* Note: The signature for run_tests in this project seems to be:
   pass_count: int ref
   fail_count: int ref
   eval_string: string -> Ast.value
   eval_string_env: string -> Ast.environment -> Ast.value * Ast.environment
   test: string -> string -> string -> unit
*)

let run_tests pass_count fail_count _eval_string _eval_string_env test =
  Printf.printf "Phase 7 — Core: String Operations:\n";
  
  Printf.printf "  Inspection:\n";
  test "is_empty true" "is_empty(\"\")" "true";
  test "is_empty false" "is_empty(\"a\")" "false";
  test "length string" "length(\"hello\")" "5";
  test "length list" "length([1, 2, 3])" "3";
  test "length vector" "length(seq(1, 10))" "10";
  test "length vector of strings" "length([\"a\", \"bc\"])" "2";
  
  Printf.printf "  Substrings:\n";
  test "substring simple" "substring(\"hello\", 1, 3)" "\"el\"";
  test "slice alias" "slice(\"hello\", 0, 5)" "\"hello\"";
  test "char_at" "char_at(\"abc\", 1)" "\"b\"";
  test "substring out of bounds" "substring(\"a\", 0, 2)" {|Error(ValueError: "Invalid substring indices.")|};
  
  Printf.printf "  Search:\n";
  test "index_of found" "index_of(\"hello\", \"l\")" "2";
  test "index_of not found" "index_of(\"hello\", \"z\")" "-1";
  test "last_index_of found" "last_index_of(\"hello\", \"l\")" "3";
  test "contains false" "contains(\"team\", \"i\")" "false"; 
  test "contains true" "contains(\"team\", \"ea\")" "true";
  test "starts_with true" "starts_with(\"prefix\", \"pre\")" "true";
  test "starts_with false" "starts_with(\"prefix\", \"fix\")" "false";
  test "ends_with true" "ends_with(\"suffix\", \"fix\")" "true";
  
  Printf.printf "  Modification:\n";
  test "replace all" "replace(\"banana\", \"a\", \"o\")" "\"bonono\"";
  test "replace first" "replace_first(\"banana\", \"a\", \"o\")" "\"bonana\"";
  
  Printf.printf "  Case:\n";
  test "to_upper" "to_upper(\"test\")" "\"TEST\"";
  test "to_lower" "to_lower(\"TEST\")" "\"test\"";
  
  Printf.printf "  Vectorization:\n";
  test "to_upper vector" "to_upper([\"hello\", \"world\"])" "Vector[\"HELLO\", \"WORLD\"]";
  test "substring vector" "substring([\"hello\", \"world\"], 1, 3)" "Vector[\"el\", \"or\"]";
  test "contains vector scalar" "contains([\"hello\", \"help\"], \"lo\")" "Vector[true, false]";

  test "join list" "join([\"a\", \"b\", \"c\"], \"-\")" "\"a-b-c\"";
  test "join vector" "join(seq(1, 3), \", \")" "\"1, 2, 3\"";
  test "join scalar" "join(\"a\", \"-\")" "\"a\"";
  test "concat error" "\"a\" + \"b\"" {|Error(TypeError: "String concatenation with '+' is not supported. Use 'join([a, b], sep)' or 'paste(a, b, sep)' instead.")|};

  print_newline ()
