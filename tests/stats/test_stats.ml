let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "Phase 5 — Stats: mean():\n";
  test "mean of int list" "mean([1, 2, 3, 4, 5])" "3.";
  test "mean of float list" "mean([1.0, 2.0, 3.0])" "2.";
  test "mean empty" "mean([])" {|Error(ValueError: "mean() called on empty list")|};
  test "mean with NA" "mean([1, NA, 3])" {|Error(TypeError: "mean() encountered NA value. Handle missingness explicitly.")|};
  test "mean non-numeric" {|mean("hello")|} {|Error(TypeError: "mean() expects a numeric List or Vector")|};
  print_newline ();

  Printf.printf "Phase 5 — Stats: sd():\n";
  test "sd of list" "sd([2, 4, 4, 4, 5, 5, 7, 9])" "2.1380899353";
  test "sd single value" "sd([42])" {|Error(ValueError: "sd() requires at least 2 values")|};
  test "sd with NA" "sd([1, NA, 3])" {|Error(TypeError: "sd() encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Stats: quantile():\n";
  test "quantile median" "quantile([1, 2, 3, 4, 5], 0.5)" "3.";
  test "quantile min" "quantile([1, 2, 3, 4, 5], 0.0)" "1.";
  test "quantile max" "quantile([1, 2, 3, 4, 5], 1.0)" "5.";
  test "quantile Q1" "quantile([1, 2, 3, 4, 5], 0.25)" "2.";
  test "quantile invalid p" "quantile([1, 2, 3], 1.5)" {|Error(ValueError: "quantile() expects a probability between 0 and 1")|};
  test "quantile empty" "quantile([], 0.5)" {|Error(ValueError: "quantile() called on empty data")|};
  print_newline ();

  Printf.printf "Phase 5 — Stats: cor():\n";
  (* Create CSV for correlation tests *)
  let csv_p5_cor = "test_phase5_cor.csv" in
  let oc_cor = open_out csv_p5_cor in
  output_string oc_cor "x,y,z,w\n1,2,6,1\n2,4,4,1\n3,6,2,1\n";
  close_out oc_cor;
  let env_cor = Eval.initial_env () in
  let (_, env_cor) = eval_string_env (Printf.sprintf {|cdf = read_csv("%s")|} csv_p5_cor) env_cor in

  let (v, _) = eval_string_env "cor(cdf.x, cdf.y)" env_cor in
  let result = Ast.Utils.value_to_string v in
  if result = "1." then begin
    incr pass_count; Printf.printf "  ✓ perfect positive correlation\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ perfect positive correlation\n    Expected: 1.\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "cor(cdf.x, cdf.z)" env_cor in
  let result = Ast.Utils.value_to_string v in
  if result = "-1." then begin
    incr pass_count; Printf.printf "  ✓ perfect negative correlation\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ perfect negative correlation\n    Expected: -1.\n    Got: %s\n" result
  end;

  test "cor non-numeric"
    {|cor("hello", "world")|}
    {|Error(TypeError: "cor() expects two numeric Vectors or Lists")|};
  test "cor with NA"
    "cor(NA, [1, 2, 3])"
    {|Error(TypeError: "cor() encountered NA value. Handle missingness explicitly.")|};

  (try Sys.remove csv_p5_cor with _ -> ());
  print_newline ();

  Printf.printf "Phase 5 — Stats: lm():\n";
  (* Create test CSV for lm() *)
  let csv_p5_lm = "test_phase5_lm.csv" in
  let oc_lm = open_out csv_p5_lm in
  output_string oc_lm "x,y\n1,2\n2,4\n3,6\n4,8\n5,10\n";
  close_out oc_lm;

  let env_lm = Eval.initial_env () in
  let (_, env_lm) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_p5_lm) env_lm in
  let (_, env_lm) = eval_string_env {|model = lm(data = df, formula = y ~ x)|} env_lm in

  let (v, _) = eval_string_env "type(model)" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = {|"Dict"|} then begin
    incr pass_count; Printf.printf "  ✓ lm() returns a Dict\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() returns a Dict\n    Expected: \"Dict\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "model.slope" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "2." then begin
    incr pass_count; Printf.printf "  ✓ lm() correct slope (2.0)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() correct slope (2.0)\n    Expected: 2.\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "model.intercept" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "0." then begin
    incr pass_count; Printf.printf "  ✓ lm() correct intercept (0.0)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() correct intercept (0.0)\n    Expected: 0.\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "model.r_squared" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "1." then begin
    incr pass_count; Printf.printf "  ✓ lm() perfect R-squared (1.0)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() perfect R-squared (1.0)\n    Expected: 1.\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "model.n" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "5" then begin
    incr pass_count; Printf.printf "  ✓ lm() correct observation count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() correct observation count\n    Expected: 5\n    Got: %s\n" result
  end;

  (* Formula type and printing tests *)
  test "formula type"
    "type(y ~ x)"
    {|"Formula"|};
  test "formula to string"
    "f = y ~ x; print(type(f))"
    "null";
  test "multi-variable formula"
    "f = mpg ~ hp + wt; type(f)"
    {|"Formula"|};

  (* lm() error handling tests *)
  test "lm missing column"
    (Printf.sprintf {|df = read_csv("%s"); lm(data = df, formula = y ~ z)|} csv_p5_lm)
    {|Error(KeyError: "Column 'z' not found in DataFrame")|};
  test "lm non-dataframe"
    {|lm(data = 42, formula = y ~ x)|}
    {|Error(TypeError: "lm() 'data' must be a DataFrame")|};
  test "lm non-formula"
    (Printf.sprintf {|df = read_csv("%s"); lm(data = df, formula = 42)|} csv_p5_lm)
    {|Error(TypeError: "lm() 'formula' must be a Formula (use ~ operator)")|};
  test "lm missing data arg"
    {|lm(formula = y ~ x)|}
    {|Error(ArityError: "lm() missing required argument 'data'")|};
  test "lm missing formula arg"
    (Printf.sprintf {|df = read_csv("%s"); lm(data = df)|} csv_p5_lm)
    {|Error(ArityError: "lm() missing required argument 'formula'")|};
  print_newline ();

  Printf.printf "Phase 5 — Stats: Pipeline integration:\n";
  test "mean in pipe"
    "[1, 2, 3, 4, 5] |> mean"
    "3.";
  test "sd in pipe"
    "[2, 4, 4, 4, 5, 5, 7, 9] |> sd"
    "2.1380899353";
  print_newline ();

  Printf.printf "Phase 5 — Functions available without imports:\n";
  test "sqrt available" "type(sqrt(4))" {|"Float"|};
  test "abs available" "type(abs(0 - 5))" {|"Int"|};
  test "log available" "type(log(1))" {|"Float"|};
  test "exp available" "type(exp(0))" {|"Float"|};
  test "pow available" "type(pow(2, 3))" {|"Float"|};
  test "mean available" "type(mean([1, 2]))" {|"Float"|};
  test "sd available" "type(sd([1, 2, 3]))" {|"Float"|};
  test "quantile available" "type(quantile([1, 2, 3], 0.5))" {|"Float"|};
  test "cor available" "type(cor([1, 2, 3], [4, 5, 6]))" {|"Float"|};
  print_newline ();

  (* Clean up Phase 5 CSV *)
  (try Sys.remove csv_p5_lm with _ -> ())
