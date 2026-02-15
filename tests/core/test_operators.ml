let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Comprehensive Operator Tests:\n";

  (* --- Arithmetic Operators --- *)
  Printf.printf "  Arithmetic:\n";
  test "Add Int" "1 + 2" "3";
  test "Add Float" "1.5 + 2.5" "4.";
  test "Add Mixed" "1 + 2.5" "3.5";
  test "Add String error" {|"a" + "b"|} {|Error(TypeError: "String concatenation with '+' is not supported. Use 'join([a, b], sep)' or 'paste(a, b, sep)' instead.")|};
  test "Sub Int" "10 - 4" "6";
  test "Mul Int" "3 * 4" "12";
  test "Div Int" "10 / 2" "5.";
  test "Div Int Float" "10 / 2.0" "5.";
  test "Div Float" "10.0 / 2.0" "5.";
  
  (* Division by Zero *)
  test "Div Zero Int" "1 / 0" {|Error(DivisionByZero: "Division by zero.")|};
  test "Div Zero Float" "1.0 / 0.0" {|Error(DivisionByZero: "Division by zero.")|};

  (* --- Comparison Operators --- *)
  Printf.printf "  Comparison:\n";
  test "Eq Int" "1 == 1" "true";
  test "Eq Float" "1.0 == 1.0" "true";
  test "Eq Mixed" "1 == 1.0" "true";
  test "Neq Int" "1 != 2" "true";
  test "Lt Int" "1 < 2" "true";
  test "Gt Int" "2 > 1" "true";
  test "LtEq Int" "1 <= 1" "true";
  test "GtEq Int" "1 >= 1" "true";

  (* --- Logical Operators --- *)
  Printf.printf "  Logical (Short-circuit):\n";
  test "And True True" "true && true" "true";
  test "And True False" "true && false" "false";
  test "And False Error" "false && (1/0)" "false"; (* Short-circuit check *)
  test "Or True Error" "true || (1/0)" "true";     (* Short-circuit check *)
  test "Or False False" "false || false" "false";
  test "Not True" "!true" "false";
  test "Not False" "!false" "true";

  (* Strict Type Checks *)
  test "And Invalid Left" "1 && true" {|Error(TypeError: "Left operand of && must be Bool, got Int")|};
  test "And Invalid Right" "true && 1" {|Error(TypeError: "Right operand of && must be Bool, got Int")|};
  test "Not Invalid" "!1" {|Error(TypeError: "Operand of 'not' must be Bool, got Int")|};

  (* --- Bitwise/Strict Boolean Operators --- *)
  Printf.printf "  Bitwise/Strict:\n";
  test "BitAnd" "true & false" "false";
  test "BitOr" "true | false" "true";
  (* No short-circuiting *)
  test "BitAnd No Short-circuit" "false & (1/0)" {|Error(DivisionByZero: "Division by zero.")|}; 
  test "BitOr No Short-circuit" "true | (1/0)" {|Error(DivisionByZero: "Division by zero.")|};

  (* --- Membership Operator --- *)
  Printf.printf "  Membership:\n";
  test "In List" "1 in [1, 2, 3]" "true";
  test "Not In List" "4 in [1, 2, 3]" "false";
  test "Vector In List" "[1, 4] in [1, 2, 3]" "[true, false]";
  test "In Strict Error" "1 in [1, 1/0]" {|Error(DivisionByZero: "Division by zero.")|};

  (* --- Broadcasting --- *)
  Printf.printf "  Broadcasting:\n";
  test "Broadcast Add Scalar" "[1, 2] .+ 1" "[2, 3]";
  test "Broadcast Add Vector" "[1, 2] .+ [3, 4]" "[4, 6]";
  test "Broadcast Eq" "[1, 2] .== 1" "[true, false]";
  test "Broadcast Gt" "[1, 2] .> 1" "[false, true]";
  test "Broadcast BitAnd" "[true, false] .& true" "[true, false]";

  (* Broadcast Error *)
  test "Broadcast Mismatch" "[1, 2] .+ [1, 2, 3]" {|Error(ValueError: "Broadcast requires lists of equal length.
Left has length 2, right has length 3.")|};

  (* --- NA Propagation --- *)
  Printf.printf "  NA Propagation:\n";
  test "NA Add" "1 + NA" {|Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "NA Eq" "1 == NA" {|Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "NA And" "true && NA" {|Error(TypeError: "Right operand of && must be Bool, got NA")|}; (* Different error path for && *)
  test "NA Or" "false || NA" {|Error(TypeError: "Right operand of || must be Bool, got NA")|}; (* Different error path for || *)
  test "NA In" "NA in [1, 2]" {|Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")|};
  test "Broadcast NA" "[1, NA] .+ 1" {|[2, Error(TypeError: "Operation on NA: NA values do not propagate implicitly. Handle missingness explicitly.")]|};
