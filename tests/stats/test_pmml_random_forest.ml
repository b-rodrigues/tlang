let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "PMML Random Forest:\n";

  test "t_read_pmml random forest model_type"
    {|m = t_read_pmml("tests/golden/data/iris_random_forest.pmml"); m.model_type|}
    {|\"random_forest\"|};

  let env = Packages.init_env () in
  let (_, env) = eval_string_env {|df = read_csv("tests/golden/data/iris.csv")|} env in
  let (_, env) = eval_string_env {|m = t_read_pmml("tests/golden/data/iris_random_forest.pmml")|} env in
  let (v, _) = eval_string_env {|head(predict(df, m))|} env in
  let result = Ast.Utils.value_to_string v in
  if result = {|\"setosa\"|} then begin
    incr pass_count; Printf.printf "  ✓ randomForest predict first label\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ randomForest predict first label\n    Expected: \"setosa\"\n    Got: %s\n" result
  end;

  print_newline ()
