let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
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
  print_newline ()
