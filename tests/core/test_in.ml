let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "In Operator:\n";

  test "scalar in list" "1 in [1, 2, 3]" "true";
  test "scalar not in list" "4 in [1, 2, 3]" "false";
  test "string in list" "'a' in ['a', 'b']" "true";
  test "string not in list" "'c' in ['a', 'b']" "false";

  (* Comparison Logic *)
  test "int in float list (relaxed numeric equality)" "1 in [1.0, 2.0]" "true"; 
  test "int in string list" "1 in ['1', '2']" "false";

  (* Vector LHS *)
  test "vector in list" "[1, 4] in [1, 2, 3]" "[true, false]";
  test "vector all in" "[1, 2] in [1, 2, 3]" "[true, true]";

  (* Error handling *)
  test "in non-list" "1 in 1" {|Error(TypeError: "Right operand of 'in' must be a List, got Int")|};
  
  (* Error propagation *)
  (* List construction is strict, so [1, 1/0] evaluates to Error before 'in' sees it. *)
  test "find before error (strict list)" "1 in [1, 1/0]" {|Error(DivisionByZero: "Division by zero")|}; 
  (* 2 is not 1, then checks next. 2 == 1/0 is Error. Propagates. *)
  test "error in list" "2 in [1, 1/0]" {|Error(DivisionByZero: "Division by zero")|}; 
  
  (* NA handling *)
  test "find before NA" "1 in [1, NA]" "true"; 
  test "NA in list error" "2 in [1, NA]" {|Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
