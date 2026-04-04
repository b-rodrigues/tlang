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
  Printf.printf "PMML Random Forest:\n";

  let root = find_repo_root () in
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
       let first = if Array.length arr > 0 then arr.(0) else Ast.(VNA Ast.NAGeneric) in
       let result = Ast.Utils.value_to_string first |> String.trim in
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

  print_newline ()
