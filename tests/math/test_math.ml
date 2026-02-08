let run_tests pass_count fail_count _eval_string eval_string_env test =
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
  print_newline ()
