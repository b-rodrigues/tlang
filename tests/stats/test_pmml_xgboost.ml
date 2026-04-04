let find_repo_root () =
  let rec loop dir =
    let marker = Filename.concat dir "summary.md" in
    if Sys.file_exists marker then dir
    else
      let parent = Filename.dirname dir in
      if parent = dir then dir else loop parent
  in
  loop (Sys.getcwd ())

let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "PMML XGBoost:\n";

  let root = find_repo_root () in
  let pmml_path = Filename.concat root "tests/golden/data/iris_xgb_bin.pmml" in
  let iris_path = Filename.concat root "tests/golden/data/iris.csv" in

  test "t_read_pmml xgboost model_type"
    (Printf.sprintf {|m = t_read_pmml("%s"); m.model_type|} (String.escaped pmml_path))
    {|\"xgboost\"|};

  let env = Packages.init_env () in
  let (_, env) =
    eval_string_env (Printf.sprintf {|df = read_csv("%s")|} (String.escaped iris_path)) env
  in
  let (_, env) =
    eval_string_env (Printf.sprintf {|m = t_read_pmml("%s")|} (String.escaped pmml_path)) env
  in
  let (v, _) = eval_string_env {|predict(df, m)|} env in
  (match v with
   | Ast.VVector arr ->
       let first = if Array.length arr > 0 then arr.(0) else Ast.(VNA Ast.NAGeneric) in
       let result = Ast.Utils.value_to_string first |> String.trim in
       let match_found =
         try
           let _ = Str.search_forward (Str.regexp "1") result 0 in
           true
         with _ -> false
       in
       if match_found then begin
         incr pass_count; Printf.printf "  ✓ xgboost predict first label\n"
       end else begin
         incr fail_count;
         Printf.printf "  ✗ xgboost predict first label\n    Expected: 1\n    Got: %s\n" result
       end
   | _ ->
       let result = Ast.Utils.value_to_string v |> String.trim in
       incr fail_count;
       Printf.printf "  ✗ xgboost predict first label\n    Expected: 1\n    Got: %s\n" result);

  test "fit_stats xgboost n_trees"
    (Printf.sprintf {|m = t_read_pmml("%s"); fs = fit_stats(m); fs.n_trees|} (String.escaped pmml_path))
    "Vector[10.]";

  test "fit_stats xgboost n_features"
    (Printf.sprintf {|m = t_read_pmml("%s"); fs = fit_stats(m); fs.n_features|} (String.escaped pmml_path))
    "Vector[1.]";

  let mtcars_pmml = Filename.concat root "tests/golden/data/mtcars_xgb_reg.pmml" in
  test "xgboost regression model_type"
    (Printf.sprintf {|m = t_read_pmml("%s"); m.model_type|} (String.escaped mtcars_pmml))
    {|\"xgboost\"|};

  test "fit_stats xgboost regression n_trees"
    (Printf.sprintf {|m = t_read_pmml("%s"); fs = fit_stats(m); fs.n_trees|} (String.escaped mtcars_pmml))
    "Vector[25.]";

  test "summary xgboost returns a Dict"
    (Printf.sprintf {|m = t_read_pmml("%s"); type(summary(m))|} (String.escaped pmml_path))
    {|"Dict"|};

  test "summary xgboost exposes n_trees"
    (Printf.sprintf {|m = t_read_pmml("%s"); summary(m)._tidy_df.n_trees|} (String.escaped pmml_path))
    "Vector[10.]";

  print_newline ()
