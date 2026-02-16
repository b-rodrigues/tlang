let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "Phase 5 — Math: sqrt():\n";
  test "sqrt of integer" "sqrt(4)" "2.";
  test "sqrt of float" "sqrt(2.0)" "1.41421356237";
  test "sqrt of 0" "sqrt(0)" "0.";
  test "sqrt negative" "sqrt(-1)" {|Error(ValueError: "Function `sqrt` is undefined for negative numbers.")|};
  test "sqrt NA" "sqrt(NA)" {|Error(TypeError: "Function `sqrt` encountered NA value. Handle missingness explicitly.")|};
  test "sqrt non-numeric" {|sqrt("hello")|} {|Error(TypeError: "Function `sqrt` expects a number, numeric Vector, or NDArray.")|};
  print_newline ();

  Printf.printf "Phase 5 — Math: abs():\n";
  test "abs of positive int" "abs(5)" "5";
  test "abs of negative int" "abs(0 - 5)" "5";
  test "abs of negative float" "abs(0.0 - 3.14)" "3.14";
  test "abs of zero" "abs(0)" "0";
  test "abs NA" "abs(NA)" {|Error(TypeError: "Function `abs` encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Math: log():\n";
  test "log of 1" "log(1)" "0.";
  test "log of positive float" "log(10)" "2.30258509299";
  test "log of 0" "log(0)" {|Error(ValueError: "Function `log` is undefined for non-positive numbers.")|};
  test "log of negative" "log(0 - 1)" {|Error(ValueError: "Function `log` is undefined for non-positive numbers.")|};
  test "log NA" "log(NA)" {|Error(TypeError: "Function `log` encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Math: exp():\n";
  test "exp of 0" "exp(0)" "1.";
  test "exp of 1" "exp(1)" "2.71828182846";
  test "exp NA" "exp(NA)" {|Error(TypeError: "Function `exp` encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Math: pow():\n";
  test "pow integer" "pow(2, 3)" "8.";
  test "pow float base" "pow(4.0, 0.5)" "2.";
  test "pow zero exponent" "pow(5, 0)" "1.";
  test "pow NA base" "pow(NA, 2)" {|Error(TypeError: "Function `pow` encountered NA value. Handle missingness explicitly.")|};
  test "pow NA exponent" "pow(2, NA)" {|Error(TypeError: "Function `pow` encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Math: Vector operations:\n";
  (* Create a CSV for vector tests *)
  let csv_p5_vec = "test_phase5_vec.csv" in
  let oc_vec = open_out csv_p5_vec in
  output_string oc_vec "a,b,c\n1,2,-1\n4,3,2\n9,4,-3\n";
  close_out oc_vec;
  let env_p5 = Packages.init_env () in
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

  Printf.printf "Phase 5 — Math: extended math():\n";
  test "round digits" "round(3.14159, digits = 2)" "3.14";
  test "floor" "floor(3.9)" "3.";
  test "ceiling" "ceiling(3.1)" "4.";
  test "ceil alias" "ceil(3.1)" "4.";
  test "trunc" "trunc(0.0 - 3.9)" "-3.";
  test "sign" "sign(0.0 - 5)" "-1.";
  test "signif" "signif(1234.567, 3)" "1230.";
  test "sin" "sin(0)" "0.";
  test "cos" "cos(0)" "1.";
  test "atan2" "atan2(1, 1)" "0.785398163397";
  test "sinh" "sinh(0)" "0.";
  print_newline ();

  Printf.printf "Phase 5 — Math: NDArray operations:\n";
  test "ndarray infer shape" "shape(ndarray([[1,2],[3,4]]))" "[2, 2]";
  test "reshape" "shape(reshape(ndarray([1,2,3,4]), [2,2]))" "[2, 2]";
  test "matmul" "matmul(ndarray([[1,2],[3,4]]), ndarray([[5,6],[7,8]]))" "NDArray(shape=[2, 2], data=[19., 22., 43., 50.])";
  test "diag from vector" "diag(ndarray([2,3,4]))" "NDArray(shape=[3, 3], data=[2., 0., 0., 0., 3., 0., 0., 0., 4.])";
  test "diag from matrix" "diag(ndarray([[1,2],[3,4]]))" "NDArray(shape=[2], data=[1., 4.])";
  test "inv 2x2" "inv(ndarray([[4,7],[2,6]]))" "NDArray(shape=[2, 2], data=[0.6, -0.7, -0.2, 0.4])";
  test "kron" "kron(ndarray([[1,2],[3,4]]), ndarray([[0,5],[6,7]]))" "NDArray(shape=[4, 4], data=[0., 5., 0., 10., 6., 7., 12., 14., 0., 15., 0., 20., 18., 21., 24., 28.])";
  test "ndarray broadcast add" "ndarray([1,2,3]) .+ 1" "NDArray(shape=[3], data=[2., 3., 4.])";
  
  (* Vectorized math function tests on NDArrays *)
  test "sqrt on ndarray" "sqrt(ndarray([[4, 9], [16, 25]]))" "NDArray(shape=[2, 2], data=[2., 3., 4., 5.])";
  test "abs on ndarray" "abs(ndarray([[-1, 2], [-3, 4]]))" "NDArray(shape=[2, 2], data=[1., 2., 3., 4.])";
  test "log on ndarray" "log(ndarray([1, 10]))" "NDArray(shape=[2], data=[0., 2.30258509299])";
  test "exp on ndarray" "exp(ndarray([0, 1]))" "NDArray(shape=[2], data=[1., 2.71828182846])";
  test "pow on ndarray" "pow(ndarray([[1, 2], [3, 4]]), 2)" "NDArray(shape=[2, 2], data=[1., 4., 9., 16.])";
  
  (* Error case tests *)
  test "ndarray with empty list" "ndarray([])" {|Error(ValueError: "NDArray shape dimensions must be strictly positive.")|};
  test "ndarray with NA values" "ndarray([1, NA, 3])" {|Error(TypeError: "NDArray cannot contain NA values. Handle missingness explicitly.")|};
  test "ndarray with non-numeric values" {|ndarray([1, "a", 3])|} {|Error(TypeError: "NDArray elements must be numeric.")|};
  test "ndarray with ragged lists" "ndarray([[1,2],[3]])" {|Error(ValueError: "Cannot create NDArray from ragged (non-rectangular) list.")|};
  test "matmul dimension mismatch" "matmul(ndarray([[1,2,3]]), ndarray([[1,2],[3,4]]))" {|Error(ValueError: "matmul inner dimensions must match.")|};
  test "matmul with non-2D arrays" "matmul(ndarray([1,2,3]), ndarray([4,5,6]))" {|Error(ValueError: "matmul expects two 2D NDArrays.")|};
  test "kron with non-2D arrays" "kron(ndarray([1,2]), ndarray([[1,2],[3,4]]))" {|Error(ValueError: "kron expects two 2D NDArrays.")|};
  test "diag with non-1D/2D ndarray" "diag(ndarray([[[1,2],[3,4]]]))" {|Error(ValueError: "diag expects a 1D or 2D NDArray.")|};
  test "inv non-square" "inv(ndarray([[1,2,3],[4,5,6]]))" {|Error(ValueError: "inv expects a square matrix.")|};
  test "inv singular matrix" "inv(ndarray([[1,2],[2,4]]))" {|Error(ValueError: "inv matrix is singular or ill-conditioned.")|};
  test "reshape incompatible element count" "reshape(ndarray([1,2,3]), [2,2])" {|Error(ValueError: "reshape target shape must preserve element count.")|};
  test "shape with non-NDArray argument" "shape([1,2,3])" {|Error(TypeError: "shape expects an NDArray.")|};
  test "reshape with non-NDArray argument" "reshape([1,2,3], [3])" {|Error(TypeError: "reshape expects (NDArray, shape).")|};
  
  (* Higher-dimensional array tests *)
  test "ndarray 3d infer shape"
    "shape(ndarray([[[1,2,3,4],[5,6,7,8],[9,10,11,12]],[[13,14,15,16],[17,18,19,20],[21,22,23,24]]]))"
    "[2, 3, 4]";
  test "reshape 3d"
    "shape(reshape(ndarray([[[1,2,3,4],[5,6,7,8],[9,10,11,12]],[[13,14,15,16],[17,18,19,20],[21,22,23,24]]]), [3,2,4]))"
    "[3, 2, 4]";
  
  print_newline ()
