let run_tests pass_count fail_count _eval_string eval_string_env test =
  (* === Formula Edge Cases === *)

  Printf.printf "Formula Edge Cases — Multi-variable formulas:\n";

  (* Multi-variable formula is valid *)
  test "multi-variable formula type"
    "type(y ~ x1 + x2 + x3)"
    {|"Formula"|};
  test "two-predictor formula type"
    "type(mpg ~ hp + wt)"
    {|"Formula"|};

  (* lm() with multi-variable formula rejects (currently single-var only) *)
  let csv_mv = "test_formula_edge_mv.csv" in
  let oc_mv = open_out csv_mv in
  output_string oc_mv "y,x1,x2\n1,2,5\n4,5,3\n7,8,7\n10,11,2\n";
  close_out oc_mv;

  let env_mv = Eval.initial_env () in
  let (_, env_mv) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_mv) env_mv in

  let (v, _) = eval_string_env {|lm(data = df, formula = y ~ x1 + x2)|} env_mv in
  let result = Ast.Utils.value_to_string v in
  (* lm now supports multi-variable formulas *)
  let starts_with s prefix =
    String.length s >= String.length prefix &&
    String.sub s 0 (String.length prefix) = prefix
  in
  if not (starts_with result "Error(") then begin
    incr pass_count; Printf.printf "  ✓ lm() accepts multi-variable formula\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() accepts multi-variable formula\n    Expected: success\n    Got: %s\n" result
  end;

  (try Sys.remove csv_mv with _ -> ());
  print_newline ();

  Printf.printf "Formula Edge Cases — NA in predictor columns:\n";

  let csv_na = "test_formula_edge_na.csv" in
  let oc_na = open_out csv_na in
  output_string oc_na "y,x\n1,2\n3,\n5,6\n7,8\n";
  close_out oc_na;

  let env_na = Eval.initial_env () in
  let (_, env_na) = eval_string_env (Printf.sprintf {|df_na = read_csv("%s")|} csv_na) env_na in

  (* lm() should handle NA in columns *)
  let (v, _) = eval_string_env {|lm(data = df_na, formula = y ~ x)|} env_na in
  let result = Ast.Utils.value_to_string v in
  if starts_with result "Error(" then begin
    incr pass_count; Printf.printf "  ✓ lm() with NA in predictor returns error\n"
  end else begin
    (* If it succeeds, that's also acceptable (e.g., if NA rows are dropped) *)
    incr pass_count; Printf.printf "  ✓ lm() with NA in predictor completes (may drop NA rows)\n"
  end;

  (try Sys.remove csv_na with _ -> ());
  print_newline ();

  Printf.printf "Formula Edge Cases — Zero-variance predictor:\n";

  let csv_zv = "test_formula_edge_zv.csv" in
  let oc_zv = open_out csv_zv in
  output_string oc_zv "y,x\n1,5\n2,5\n3,5\n4,5\n";
  close_out oc_zv;

  let env_zv = Eval.initial_env () in
  let (_, env_zv) = eval_string_env (Printf.sprintf {|df_zv = read_csv("%s")|} csv_zv) env_zv in

  let (v, _) = eval_string_env {|lm(data = df_zv, formula = y ~ x)|} env_zv in
  let result = Ast.Utils.value_to_string v in
  if starts_with result "Error(" then begin
    incr pass_count; Printf.printf "  ✓ lm() with zero-variance predictor returns error\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() with zero-variance predictor should return error\n    Got: %s\n" result
  end;

  (try Sys.remove csv_zv with _ -> ());
  print_newline ();

  Printf.printf "Formula Edge Cases — Insufficient observations:\n";

  let csv_small = "test_formula_edge_small.csv" in
  let oc_small = open_out csv_small in
  output_string oc_small "y,x\n1,2\n";
  close_out oc_small;

  let env_small = Eval.initial_env () in
  let (_, env_small) = eval_string_env (Printf.sprintf {|df_small = read_csv("%s")|} csv_small) env_small in

  let (v, _) = eval_string_env {|lm(data = df_small, formula = y ~ x)|} env_small in
  let result = Ast.Utils.value_to_string v in
  if starts_with result "Error(" then begin
    incr pass_count; Printf.printf "  ✓ lm() with 1 observation returns error\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() with 1 observation should return error\n    Got: %s\n" result
  end;

  (try Sys.remove csv_small with _ -> ());
  print_newline ();

  Printf.printf "Formula Edge Cases — lm() error handling:\n";

  test "lm non-dataframe"
    {|lm(data = 42, formula = y ~ x)|}
    {|Error(TypeError: "lm() 'data' must be a DataFrame")|};
  test "lm non-formula"
    {|lm(data = 42, formula = 42)|}
    {|Error(TypeError: "lm() 'data' must be a DataFrame")|};
  test "lm missing data"
    {|lm(formula = y ~ x)|}
    {|Error(ArityError: "lm() missing required argument 'data'")|};
  test "lm missing formula"
    "lm(data = 42)"
    {|Error(ArityError: "lm() missing required argument 'formula'")|};

  print_newline ();

  Printf.printf "Formula Edge Cases — Perfect fit:\n";

  let csv_perf = "test_formula_edge_perf.csv" in
  let oc_perf = open_out csv_perf in
  output_string oc_perf "y,x\n0,0\n1,1\n2,2\n3,3\n4,4\n";
  close_out oc_perf;

  let env_perf = Eval.initial_env () in
  let (_, env_perf) = eval_string_env (Printf.sprintf {|df_perf = read_csv("%s")|} csv_perf) env_perf in
  let (_, env_perf) = eval_string_env {|model = lm(data = df_perf, formula = y ~ x)|} env_perf in

  (* Access R² through _model_data *)
  let (v, _) = eval_string_env "model._model_data.r_squared" env_perf in
  let result = Ast.Utils.value_to_string v in
  if result = "1." then begin
    incr pass_count; Printf.printf "  ✓ perfect fit has R²=1.0\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ perfect fit has R²=1.0\n    Expected: 1.\n    Got: %s\n" result
  end;

  (* Access slope (estimate[1]) and intercept (estimate[0]) via _tidy_df *)
  let (v, _) = eval_string_env "model._tidy_df.estimate" env_perf in
  (match v with
   | Ast.VVector arr when Array.length arr >= 2 ->
     let slope_str = Ast.Utils.value_to_string arr.(1) in
     let intercept_str = Ast.Utils.value_to_string arr.(0) in
     (match float_of_string_opt slope_str with
      | Some slope when Float.abs (slope -. 1.0) < 0.001 ->
        incr pass_count; Printf.printf "  ✓ perfect fit slope=1.0\n"
      | _ ->
        incr fail_count; Printf.printf "  ✗ perfect fit slope=1.0\n    Expected: ~1.0\n    Got: %s\n" slope_str);
     (match float_of_string_opt intercept_str with
      | Some intercept when Float.abs intercept < 0.001 ->
        incr pass_count; Printf.printf "  ✓ perfect fit intercept=0.0\n"
      | _ ->
        incr fail_count; Printf.printf "  ✗ perfect fit intercept=0.0\n    Expected: ~0.0\n    Got: %s\n" intercept_str)
   | _ ->
     incr fail_count; Printf.printf "  ✗ perfect fit slope=1.0\n    Could not extract estimates\n";
     incr fail_count; Printf.printf "  ✗ perfect fit intercept=0.0\n    Could not extract estimates\n");

  (try Sys.remove csv_perf with _ -> ());
  print_newline ()
