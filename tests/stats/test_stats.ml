let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "Phase 5 — Stats: mean():\n";
  test "mean of int list" "mean([1, 2, 3, 4, 5])" "3.";
  test "mean of float list" "mean([1.0, 2.0, 3.0])" "2.";
  test "mean empty" "mean([])" {|Error(ValueError: "Function `mean` called on empty List.")|};
  test "mean with NA" "mean([1, NA, 3])" {|Error(TypeError: "Function `mean` encountered NA value. Handle missingness explicitly.")|};
  test "mean non-numeric" {|mean("hello")|} {|Error(TypeError: "Function `mean` expects a numeric List or Vector.")|};
  test "mean na_rm=true skips NA" "mean([1.0, 2.0, NA, 4.0], na_rm = true)" "2.33333333333";
  test "mean na_rm=true no NAs" "mean([1.0, 2.0, 3.0], na_rm = true)" "2.";
  test "mean na_rm=true all NAs" "mean([NA, NA, NA], na_rm = true)" "NA(Float)";
  test "mean na_rm=false with NA errors" "mean([1, NA, 3], na_rm = false)" {|Error(TypeError: "Function `mean` encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Stats: sum() with na_rm:\n";
  test "sum na_rm=true skips NA" "sum([1, NA, 3], na_rm = true)" "4";
  test "sum na_rm=true no NAs" "sum([1, 2, 3], na_rm = true)" "6";
  test "sum na_rm=true all NAs" "sum([NA, NA, NA], na_rm = true)" "0";
  test "sum na_rm=false with NA errors" "sum([1, NA, 3], na_rm = false)" {|Error(TypeError: "Function `sum` encountered NA value. Handle missingness explicitly.")|};
  test "sum na_rm=true float" "sum([1.5, NA, 2.5], na_rm = true)" "4.";
  print_newline ();

  Printf.printf "Phase 5 — Stats: sd():\n";
  test "sd of list" "sd([2, 4, 4, 4, 5, 5, 7, 9])" "2.1380899353";
  test "sd single value" "sd([42])" {|Error(ValueError: "Function `sd` requires at least 2 values.")|};
  test "sd with NA" "sd([1, NA, 3])" {|Error(TypeError: "Function `sd` encountered NA value. Handle missingness explicitly.")|};
  test "sd na_rm=true skips NA" "sd([2, 4, NA, 4, 5, 5, NA, 9], na_rm = true)" "2.31660671385";
  test "sd na_rm=true no NAs" "sd([2, 4, 4, 4, 5, 5, 7, 9], na_rm = true)" "2.1380899353";
  test "sd na_rm=true all NAs" "sd([NA, NA, NA], na_rm = true)" "NA(Float)";
  test "sd na_rm=false with NA errors" "sd([1, NA, 3], na_rm = false)" {|Error(TypeError: "Function `sd` encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  Printf.printf "Phase 5 — Stats: quantile():\n";
  test "quantile median" "quantile([1, 2, 3, 4, 5], 0.5)" "3.";
  test "quantile min" "quantile([1, 2, 3, 4, 5], 0.0)" "1.";
  test "quantile max" "quantile([1, 2, 3, 4, 5], 1.0)" "5.";
  test "quantile Q1" "quantile([1, 2, 3, 4, 5], 0.25)" "2.";
  test "quantile invalid p" "quantile([1, 2, 3], 1.5)" {|Error(ValueError: "Function `quantile` expects a probability between 0 and 1.")|};
  test "quantile empty" "quantile([], 0.5)" {|Error(ValueError: "Function `quantile` called on empty data.")|};
  test "quantile na_rm=true skips NA" "quantile([1, NA, 3, NA, 5], 0.5, na_rm = true)" "3.";
  test "quantile na_rm=true no NAs" "quantile([1, 2, 3, 4, 5], 0.5, na_rm = true)" "3.";
  test "quantile na_rm=true all NAs" "quantile([NA, NA, NA], 0.5, na_rm = true)" "NA(Float)";
  test "quantile na_rm=false with NA errors" "quantile([1, NA, 3], 0.5, na_rm = false)" {|Error(TypeError: "Function `quantile` encountered NA value. Handle missingness explicitly.")|};
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
    {|Error(TypeError: "Function `cor` expects two numeric Vectors or Lists.")|};
  test "cor with NA"
    "cor(NA, [1, 2, 3])"
    {|Error(TypeError: "Function `cor` encountered NA value. Handle missingness explicitly.")|};
  test "cor na_rm=true pairwise deletion" "cor([1, NA, 3, 4, 5], [2, 4, NA, 8, 10], na_rm = true)" "1.";
  test "cor na_rm=true no NAs" "cor([1, 2, 3], [2, 4, 6], na_rm = true)" "1.";
  test "cor na_rm=true all NAs" "cor([NA, NA, NA], [NA, NA, NA], na_rm = true)" "NA(Float)";
  test "cor na_rm=false with NA errors"
    "cor([1, NA, 3], [4, 5, 6], na_rm = false)"
    {|Error(TypeError: "Function `cor` encountered NA value. Handle missingness explicitly.")|};

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

  (* lm() now returns a VDict with _tidy_df and _model_data *)
  let (v, _) = eval_string_env "type(model)" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = {|"Dict"|} then begin
    incr pass_count; Printf.printf "  ✓ lm() returns a Dict (model object)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() returns a Dict (model object)\n    Expected: \"Dict\"\n    Got: %s\n" result
  end;

  (* Model object has accessible formula *)
  let (v, _) = eval_string_env "model.formula" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "y ~ x" then begin
    incr pass_count; Printf.printf "  ✓ model.formula shows formula\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ model.formula shows formula\n    Expected: y ~ x\n    Got: %s\n" result
  end;

  (* Model object has R² *)
  let (v, _) = eval_string_env "model.r_squared" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "1." then begin
    incr pass_count; Printf.printf "  ✓ model.r_squared = 1.0 (perfect fit)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ model.r_squared = 1.0 (perfect fit)\n    Expected: 1.\n    Got: %s\n" result
  end;

  (* Model object has nobs *)
  let (v, _) = eval_string_env "model.nobs" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "5" then begin
    incr pass_count; Printf.printf "  ✓ model.nobs = 5\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ model.nobs = 5\n    Expected: 5\n    Got: %s\n" result
  end;

  (* summary(model) returns a tidy DataFrame *)
  let (v, _) = eval_string_env "type(summary(model))" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = {|"DataFrame"|} then begin
    incr pass_count; Printf.printf "  ✓ summary(model) returns a DataFrame\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ summary(model) returns a DataFrame\n    Expected: \"DataFrame\"\n    Got: %s\n" result
  end;

  (* summary() has correct columns *)
  let (v, _) = eval_string_env "colnames(summary(model))" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = {|["term", "estimate", "std_error", "statistic", "p_value"]|} then begin
    incr pass_count; Printf.printf "  ✓ summary() tidy DataFrame has correct columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ summary() tidy DataFrame has correct columns\n    Expected: [\"term\", \"estimate\", \"std_error\", \"statistic\", \"p_value\"]\n    Got: %s\n" result
  end;

  (* summary() has 2 rows (intercept + x) *)
  let (v, _) = eval_string_env "nrow(summary(model))" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ summary() has 2 rows\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ summary() has 2 rows\n    Expected: 2\n    Got: %s\n" result
  end;

  (* Test fit_stats() *)
  let (v, _) = eval_string_env "type(fit_stats(model))" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = {|"DataFrame"|} then begin
    incr pass_count; Printf.printf "  ✓ fit_stats() returns a DataFrame\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ fit_stats() returns a DataFrame\n    Expected: \"DataFrame\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "nrow(fit_stats(model))" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "1" then begin
    incr pass_count; Printf.printf "  ✓ fit_stats() returns 1 row\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ fit_stats() returns 1 row\n    Expected: 1\n    Got: %s\n" result
  end;

  (* Test add_diagnostics() *)
  let (v, _) = eval_string_env "type(add_diagnostics(model, data = df))" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = {|"DataFrame"|} then begin
    incr pass_count; Printf.printf "  ✓ add_diagnostics() returns a DataFrame\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ add_diagnostics() returns a DataFrame\n    Expected: \"DataFrame\"\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "nrow(add_diagnostics(model, data = df))" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "5" then begin
    incr pass_count; Printf.printf "  ✓ add_diagnostics() preserves row count\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ add_diagnostics() preserves row count\n    Expected: 5\n    Got: %s\n" result
  end;

  (* Check add_diagnostics has diagnostic columns *)
  let (v, _) = eval_string_env "colnames(add_diagnostics(model, data = df))" env_lm in
  let result = Ast.Utils.value_to_string v in
  let has_fitted = String.length result > 0 && (try let _ = Str.search_forward (Str.regexp_string ".fitted") result 0 in true with Not_found -> false) in
  let has_resid = String.length result > 0 && (try let _ = Str.search_forward (Str.regexp_string ".resid") result 0 in true with Not_found -> false) in
  if has_fitted && has_resid then begin
    incr pass_count; Printf.printf "  ✓ add_diagnostics() adds .fitted and .resid columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ add_diagnostics() adds .fitted and .resid columns\n    Got columns: %s\n" result
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
    {|Error(KeyError: "Column `z` not found in DataFrame.")|};
  test "lm non-dataframe"
    {|lm(data = 42, formula = y ~ x)|}
    {|Error(TypeError: "Function `lm` 'data' must be a DataFrame.")|};
  test "lm non-formula"
    (Printf.sprintf {|df = read_csv("%s"); lm(data = df, formula = 42)|} csv_p5_lm)
    {|Error(TypeError: "Function `lm` 'formula' must be a Formula (use ~ operator).")|};
  test "lm missing data arg"
    {|lm(formula = y ~ x)|}
    {|Error(ArityError: "Function `lm` missing required argument 'data'.")|};
  test "lm missing formula arg"
    (Printf.sprintf {|df = read_csv("%s"); lm(data = df)|} csv_p5_lm)
    {|Error(ArityError: "Function `lm` missing required argument 'formula'.")|};
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
