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
  Printf.printf "PMML LightGBM:\n";

  let root = find_repo_root () in
  let pmml_path = Filename.concat root "tests/golden/data/iris_lgb_bin.pmml" in
  let iris_path = Filename.concat root "tests/golden/data/iris.csv" in

  test "t_read_pmml lightgbm model_type"
    (Printf.sprintf {|m = t_read_pmml("%s"); m.model_type|} (String.escaped pmml_path))
    {|\"lightgbm\"|};

  let env = Packages.init_env () in
  let (_, env) =
    eval_string_env (Printf.sprintf {|df = read_csv("%s") |> clean_colnames()|} (String.escaped iris_path)) env
  in
  let (_, env) =
    eval_string_env (Printf.sprintf {|m = t_read_pmml("%s")|} (String.escaped pmml_path)) env
  in
  let (v, _) = eval_string_env {|predict(df, m)|} env in
  (match v with
   | Ast.VVector arr ->
       let first = if Array.length arr > 0 then arr.(0) else Ast.VNull in
       let result = Ast.Utils.value_to_string first |> String.trim in
       if result = "1" then begin
         incr pass_count; Printf.printf "  ✓ lightgbm predict first label\n"
       end else begin
         incr fail_count;
         Printf.printf "  ✗ lightgbm predict first label\n    Expected: 1\n    Got: %s\n" result
       end
   | _ ->
       let result = Ast.Utils.value_to_string v |> String.trim in
       incr fail_count;
       Printf.printf "  ✗ lightgbm predict first label\n    Expected: 1\n    Got: %s\n" result);

  test "fit_stats lightgbm n_trees"
    (Printf.sprintf {|m = t_read_pmml("%s"); fs = fit_stats(m); fs.n_trees|} (String.escaped pmml_path))
    "Vector[10.]";

  let mtcars_pmml = Filename.concat root "tests/golden/data/mtcars_lgb_reg.pmml" in
  test "lightgbm regression model_type"
    (Printf.sprintf {|m = t_read_pmml("%s"); m.model_type|} (String.escaped mtcars_pmml))
    {|\"lightgbm\"|};

  test "fit_stats lightgbm regression n_trees"
    (Printf.sprintf {|m = t_read_pmml("%s"); fs = fit_stats(m); fs.n_trees|} (String.escaped mtcars_pmml))
    "Vector[20.]";

  test "summary lightgbm returns a Dict"
    (Printf.sprintf {|m = t_read_pmml("%s"); type(summary(m))|} (String.escaped pmml_path))
    {|"Dict"|};

  test "summary lightgbm exposes n_trees"
    (Printf.sprintf {|m = t_read_pmml("%s"); summary(m)._tidy_df.n_trees|} (String.escaped pmml_path))
    "Vector[10.]";

  print_newline ()
