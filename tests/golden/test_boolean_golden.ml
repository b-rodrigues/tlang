(* tests/golden/test_boolean_golden.ml *)
(* Phase 8: Golden tests for Boolean operations *)

let run_tests _pass_count _fail_count _eval_string _eval_string_env test =
  Printf.printf "Phase 8 — Golden: Boolean Operations (ifelse / case_when):\n";

  (* ===================================================================== *)
  (* ifelse() Golden Tests                                                 *)
  (* ===================================================================== *)

  (* R: ifelse(c(TRUE, FALSE, TRUE), 1, 0) => 1, 0, 1 *)
  test "golden boolean: ifelse basic"
    {|ifelse([true, false, true], 1, 0)|}
    "Vector[1, 0, 1]";

  (* R: ifelse(c(TRUE, FALSE, NA), 1, 0) => 1, 0, NA *)
  test "golden boolean: ifelse with NA in condition"
    {|ifelse([true, false, NA], 1, 0)|}
    "Vector[1, 0, NA]";

  (* R: ifelse(TRUE, c(1, 2), c(3, 4)) => 1 *)
  test "golden boolean: ifelse vectorized vectors"
    {|ifelse([true, false], [1, 2], [3, 4])|}
    "Vector[1, 4]";
    
  test "golden boolean: ifelse scalar condition"
    {|ifelse(true, [1, 2], [3, 4])|}
    "Vector[1]";

  (* Type promotion: Int + Float -> Float *)
  test "golden boolean: ifelse type promotion"
    {|ifelse([true, false], 1, 2.5)|}
    "Vector[1., 2.5]";

  (* Explicit missing value *)
  test "golden boolean: ifelse explicit missing"
    {|ifelse([true, false, NA], 1, 0, 999)|}
    "Vector[1, 0, 999]";

  (* ===================================================================== *)
  (* case_when() Golden Tests                                              *)
  (* ===================================================================== *)

  (* R: case_when(x < 0 ~ "Neg", x > 0 ~ "Pos") *)
  test "golden boolean: case_when basic"
    {|x = [-5, 0, 5]; casewhen(x .< 0 ~ "Neg", x .> 0 ~ "Pos", .default = "Zero")|}
    {|Vector["Neg", "Zero", "Pos"]|};

  (* R: casewhen(x %% 2 == 0 ~ "Even", .default = "Odd") *)
  (* Using % for modulo now that we added it *)
  test "golden boolean: case_when default"
    {|x = [1, 2, 3, 4]; casewhen(x .% 2 .== 0 ~ "Even", .default = "Odd")|}
    {|Vector["Odd", "Even", "Odd", "Even"]|};

  (* R: case_when matching first condition *)
  test "golden boolean: case_when priority"
    {|x = 10; casewhen(x > 5 ~ "Gt5", x > 8 ~ "Gt8")|}
    {|Vector["Gt5"]|};

  (* Type promotion in case_when *)
  test "golden boolean: case_when type promotion"
    {|casewhen(true ~ 1, false ~ 2.5)|}
    "Vector[1.]";
  
  print_newline ()
