let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "PMML Random Forest:\n";

  let root = Test_helpers.find_repo_root () in
  let pmml_path = Filename.concat root "tests/golden/data/iris_random_forest.pmml" in
  let iris_path = Filename.concat root "tests/golden/data/iris.csv" in

  test "t_read_pmml random forest model_type"
    (Printf.sprintf {|m = t_read_pmml("%s"); m.model_type|} (String.escaped pmml_path))
    {|\"random_forest\"|};

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
       let first_val = if Array.length arr > 0 then arr.(0) else Ast.(VNA Ast.NAGeneric) in
       let result = Ast.Utils.value_to_string first_val |> String.trim in
       let match_found =
         try
           let _ = Str.search_forward (Str.regexp "setosa") result 0 in
           true
         with _ -> false
       in
       if match_found then begin
         incr pass_count; Printf.printf "  ✓ randomForest predict first label\n"
       end else begin
         incr fail_count;
         Printf.printf "  ✗ randomForest predict first label\n    Expected: \"setosa\"\n    Got: %s\n" result
       end
   | Ast.VDataFrame { arrow_table = table; _ } ->
       (match Arrow_table.column_names table with
        | [] ->
            incr fail_count;
            Printf.printf "  ✗ randomForest predict first label\n    Expected: \"setosa\"\n    Got: prediction DataFrame has no columns\n"
        | col_name :: _ ->
       let col = Arrow_table.get_string_column table col_name in
       let first_val = if Array.length col > 0 then match col.(0) with Some s -> Ast.VString s | None -> Ast.VNA Ast.NAString else Ast.VNA Ast.NAGeneric in
       let result = Ast.Utils.value_to_string first_val |> String.trim in
       let match_found =
         try
           let _ = Str.search_forward (Str.regexp "setosa") result 0 in
           true
         with _ -> false
       in
       if match_found then begin
         incr pass_count; Printf.printf "  ✓ randomForest predict first label\n"
       end else begin
         incr fail_count;
         Printf.printf "  ✗ randomForest predict first label\n    Expected: \"setosa\"\n    Got: %s\n" result
       end)
   | _ ->
       let result = Ast.Utils.value_to_string v |> String.trim in
       incr fail_count;
       Printf.printf "  ✗ randomForest predict first label\n    Expected: \"setosa\"\n    Got: %s\n" result);

  let (stats_v, _) = eval_string_env {|fit_stats(m) |> colnames()|} env in
  let stats_cols = Ast.Utils.value_to_string stats_v |> String.trim in
  let has_trees =
    try
      let _ = Str.search_forward (Str.regexp "n_trees") stats_cols 0 in
      true
    with _ -> false
  in
  if has_trees then begin
    incr pass_count; Printf.printf "  ✓ randomForest fit_stats includes n_trees\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ randomForest fit_stats includes n_trees\n    Expected: column n_trees\n    Got: %s\n" stats_cols
  end;

  test "summary random forest returns a Dict"
    (Printf.sprintf {|m = t_read_pmml("%s"); type(summary(m))|} (String.escaped pmml_path))
    {|"Dict"|};

  let (summary_cols_v, _) = eval_string_env {|summary(m)._tidy_df |> colnames()|} env in
  let summary_cols = Ast.Utils.value_to_string summary_cols_v |> String.trim in
  let has_summary_trees =
    try
      let _ = Str.search_forward (Str.regexp "n_trees") summary_cols 0 in
      true
    with _ -> false
  in
  if has_summary_trees then begin
    incr pass_count; Printf.printf "  ✓ randomForest summary exposes model metrics\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ randomForest summary exposes model metrics\n    Expected: column n_trees\n    Got: %s\n" summary_cols
  end;

  print_newline ()
