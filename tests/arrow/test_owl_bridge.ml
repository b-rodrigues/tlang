(* tests/arrow/test_owl_bridge.ml *)
(* Tests for the Arrow-Owl bridge module *)

let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "Arrow-Owl Bridge — numeric_column_to_owl:\n";

  (* Create test CSV for bridge tests *)
  let csv_bridge = "test_owl_bridge.csv" in
  let oc = open_out csv_bridge in
  output_string oc "x,y,name,flag\n1,2.5,alice,true\n2,4.5,bob,true\n3,6.5,charlie,false\n";
  close_out oc;

  let env = Eval.initial_env () in
  let (_, env) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_bridge) env in

  (* Test: bridge extracts int column as float array *)
  let (v, _) = eval_string_env "nrow(df)" env in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ bridge test setup (3 rows)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ bridge test setup\n    Expected: 3\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Arrow-Owl Bridge — lm() via bridge:\n";
  (* Test that lm() still works correctly through the bridge *)
  let csv_lm = "test_owl_bridge_lm.csv" in
  let oc_lm = open_out csv_lm in
  output_string oc_lm "x,y\n1,3\n2,5\n3,7\n4,9\n5,11\n";
  close_out oc_lm;

  let env_lm = Eval.initial_env () in
  let (_, env_lm) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_lm) env_lm in
  let (_, env_lm) = eval_string_env {|model = lm(data = df, formula = y ~ x)|} env_lm in

  (* New lm() returns tidy model: check via _model_data *)
  (* slope should be 2.0 (y = 2x + 1), accessed via tidy_df estimate[1] *)
  let (v, _) = eval_string_env "model._tidy_df.estimate" env_lm in
  (match v with
   | Ast.VVector arr when Array.length arr >= 2 ->
     let slope_str = Ast.Utils.value_to_string arr.(1) in
     let intercept_str = Ast.Utils.value_to_string arr.(0) in
     (match float_of_string_opt slope_str with
      | Some slope when Float.abs (slope -. 2.0) < 0.001 ->
        incr pass_count; Printf.printf "  ✓ lm() via bridge: correct slope (2.0)\n"
      | _ ->
        incr fail_count; Printf.printf "  ✗ lm() via bridge: correct slope\n    Expected: ~2.0\n    Got: %s\n" slope_str);
     (match float_of_string_opt intercept_str with
      | Some intercept when Float.abs (intercept -. 1.0) < 0.001 ->
        incr pass_count; Printf.printf "  ✓ lm() via bridge: correct intercept (1.0)\n"
      | _ ->
        incr fail_count; Printf.printf "  ✗ lm() via bridge: correct intercept\n    Expected: ~1.0\n    Got: %s\n" intercept_str)
   | _ ->
     incr fail_count; Printf.printf "  ✗ lm() via bridge: correct slope\n    Could not extract estimates\n";
     incr fail_count; Printf.printf "  ✗ lm() via bridge: correct intercept\n    Could not extract estimates\n");

  (* r_squared should be 1.0 for perfect linear data *)
  let (v, _) = eval_string_env "model._model_data.r_squared" env_lm in
  let result = Ast.Utils.value_to_string v in
  if result = "1." then begin
    incr pass_count; Printf.printf "  ✓ lm() via bridge: perfect R-squared\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ lm() via bridge: R-squared\n    Expected: 1.\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Arrow-Owl Bridge — cor() via bridge:\n";
  let csv_cor = "test_owl_bridge_cor.csv" in
  let oc_cor = open_out csv_cor in
  output_string oc_cor "a,b,c\n1,10,6\n2,20,4\n3,30,2\n";
  close_out oc_cor;

  let env_cor = Eval.initial_env () in
  let (_, env_cor) = eval_string_env (Printf.sprintf {|df = read_csv("%s")|} csv_cor) env_cor in

  (* Perfect positive correlation *)
  let (v, _) = eval_string_env "cor(df.a, df.b)" env_cor in
  let result = Ast.Utils.value_to_string v in
  if result = "1." then begin
    incr pass_count; Printf.printf "  ✓ cor() via bridge: perfect positive correlation\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ cor() via bridge: positive correlation\n    Expected: 1.\n    Got: %s\n" result
  end;

  (* Perfect negative correlation *)
  let (v, _) = eval_string_env "cor(df.a, df.c)" env_cor in
  let result = Ast.Utils.value_to_string v in
  if result = "-1." then begin
    incr pass_count; Printf.printf "  ✓ cor() via bridge: perfect negative correlation\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ cor() via bridge: negative correlation\n    Expected: -1.\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Arrow-Owl Bridge — error handling:\n";
  test "lm via bridge: missing column"
    (Printf.sprintf {|df = read_csv("%s"); lm(data = df, formula = y ~ z)|} csv_lm)
    {|Error(KeyError: "Column `z` not found in DataFrame.")|};
  test "lm via bridge: non-dataframe"
    {|lm(data = 42, formula = y ~ x)|}
    {|Error(TypeError: "Function `lm` 'data' must be a DataFrame.")|};
  test "cor via bridge: NA value"
    "cor(NA, [1, 2, 3])"
    {|Error(TypeError: "Function `cor` encountered NA value. Handle missingness explicitly.")|};
  print_newline ();

  (* Clean up test CSVs *)
  (try Sys.remove csv_bridge with _ -> ());
  (try Sys.remove csv_lm with _ -> ());
  (try Sys.remove csv_cor with _ -> ())
