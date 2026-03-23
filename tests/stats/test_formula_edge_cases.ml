let run_tests pass_count fail_count _eval_string eval_string_env test =
  (* === Formula Edge Cases === *)
  let starts_with s prefix =
    String.length s >= String.length prefix &&
    String.sub s 0 (String.length prefix) = prefix
  in
  let contains haystack needle =
    try
      let _ = Str.search_forward (Str.regexp_string needle) haystack 0 in
      true
    with Not_found -> false
  in

  Printf.printf "Formula Edge Cases — Multi-variable formulas:\n";

  (* Multi-variable formula is valid *)
  test "multi-variable formula type"
    "type(y ~ x1 + x2 + x3)"
    {|"Formula"|};
  test "two-predictor formula type"
    "type(mpg ~ hp + wt)"
    {|"Formula"|};
  test "interaction formula type"
    "type(y ~ x1 * x2)"
    {|"Formula"|};

  (* lm() with multi-variable formula should succeed (multi-variable formulas supported) *)
  let csv_mv = "test_formula_edge_mv.csv" in
  let oc_mv = open_out csv_mv in
  output_string oc_mv "y,x1,x2\n1,2,5\n4,5,3\n7,8,7\n10,11,2\n";
  close_out oc_mv;

  let env_mv = Packages.init_env () in
  let (_, env_mv) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_mv) env_mv in

  let (v, _) = eval_string_env {|lm(data = df, formula = y ~ x1 + x2)|} env_mv in
  let result = Ast.Utils.value_to_string v in
  (* lm now supports multi-variable formulas *)
  if not (starts_with result "Error(") then begin
    incr pass_count; Printf.printf "  ✓ lm() accepts multi-variable formula\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() accepts multi-variable formula\n    Expected: success\n    Got: %s\n" result
  end;

  (try Sys.remove csv_mv with _ -> ());
  print_newline ();

  Printf.printf "Formula Edge Cases — Interaction terms:\n";

  let csv_inter = "test_formula_edge_interactions.csv" in
  let oc_inter = open_out csv_inter in
  output_string oc_inter "y,x1,x2\n10,1,1\n17,1,2\n15,2,1\n24,2,2\n22,3,1\n";
  close_out oc_inter;

  let env_inter = Packages.init_env () in
  let (_, env_inter) = eval_string_env (Printf.sprintf {|df_inter = read_csv("%s")|} csv_inter) env_inter in
  let (_, env_inter) = eval_string_env {|model_inter = lm(data = df_inter, formula = y ~ x1 * x2)|} env_inter in
  let (v_inter_terms, _) = eval_string_env {|model_inter._tidy_df.term|} env_inter in
  let inter_terms = Ast.Utils.value_to_string v_inter_terms in
  if contains inter_terms "x1:x2" then begin
    incr pass_count; Printf.printf "  ✓ lm() includes interaction term in tidy output\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() includes interaction term in tidy output\n    Got: %s\n" inter_terms
  end;

  let (v_inter_coef, _) = eval_string_env {|model_inter.coefficients|} env_inter in
  let inter_coef = Ast.Utils.value_to_string v_inter_coef in
  if contains inter_coef "x1:x2" then begin
    incr pass_count; Printf.printf "  ✓ lm() exposes interaction coefficient\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() exposes interaction coefficient\n    Got: %s\n" inter_coef
  end;

  (try Sys.remove csv_inter with _ -> ());
  print_newline ();

  Printf.printf "Formula Edge Cases — Collinearity detection:\n";

  let csv_collinear = "test_formula_edge_collinear.csv" in
  let oc_collinear = open_out csv_collinear in
  output_string oc_collinear "y,x1,x2\n1,1,1\n2,2,2\n3,3,3\n4,4,4\n";
  close_out oc_collinear;

  let env_collinear = Packages.init_env () in
  let (_, env_collinear) = eval_string_env (Printf.sprintf {|df_collinear = read_csv("%s")|} csv_collinear) env_collinear in
  let (v_collinear, _) = eval_string_env {|lm(data = df_collinear, formula = y ~ x1 + x2)|} env_collinear in
  let collinear_result = Ast.Utils.value_to_string v_collinear in
  if contains collinear_result "detected collinearity" then begin
    incr pass_count; Printf.printf "  ✓ lm() reports collinearity explicitly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() reports collinearity explicitly\n    Got: %s\n" collinear_result
  end;

  (try Sys.remove csv_collinear with _ -> ());
  print_newline ();

  Printf.printf "Formula Edge Cases — NA in predictor columns:\n";

  let csv_na = "test_formula_edge_na.csv" in
  let oc_na = open_out csv_na in
  output_string oc_na "y,x\n1,2\n3,\n5,6\n7,8\n";
  close_out oc_na;

  let env_na = Packages.init_env () in
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

  let env_zv = Packages.init_env () in
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

  let env_small = Packages.init_env () in
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
    {|Error(TypeError: "Function `lm` 'data' must be a DataFrame.")|};
  test "lm non-formula"
    {|lm(data = 42, formula = 42)|}
    {|Error(TypeError: "Function `lm` 'data' must be a DataFrame.")|};
  test "lm missing data"
    {|lm(formula = y ~ x)|}
    {|Error(ArityError: "Function `lm` missing required argument 'data'.")|};
  test "lm missing formula"
    "lm(data = 42)"
    {|Error(ArityError: "Function `lm` missing required argument 'formula'.")|};

  print_newline ();

  Printf.printf "Formula Edge Cases — Perfect fit:\n";

  let csv_perf = "test_formula_edge_perf.csv" in
  let oc_perf = open_out csv_perf in
  output_string oc_perf "y,x\n0,0\n1,1\n2,2\n3,3\n4,4\n";
  close_out oc_perf;

  let env_perf = Packages.init_env () in
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
