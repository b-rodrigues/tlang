let run_tests _pass_count _fail_count _failures _eval_string eval_string_env test test_env _test_equal =
  Printf.printf "Phase 6 — Intent Blocks:\n";
  test "intent block creation"
    {|intent { description: "Load data", assumes: "File exists" }|}
    {|Intent{description: "Load data", assumes: "File exists"}|};
  test "intent type"
    {|type(intent { description: "test" })|}
    {|"Intent"|};
  test "intent block assignment"
    {|i = intent { goal: "compute mean" }; type(i)|}
    {|"Intent"|};
  test "intent block with expression values"
    {|x = "dynamic"; intent { note: x }|}
    {|Intent{note: "dynamic"}|};
  print_newline ();

  Printf.printf "Phase 6 — Intent Fields:\n";
  test "intent_fields returns Dict"
    {|i = intent { description: "test", version: "1.0" }; type(intent_fields(i))|}
    {|"Dict"|};
  test "intent_fields values"
    {|i = intent { a: "hello", b: "world" }; intent_fields(i)|}
    {|{`a`: "hello", `b`: "world"}|};
  test "intent_fields on non-intent"
    "intent_fields(42)"
    {|Error(TypeError: "Function `intent_fields` expects an Intent value.")|};
  print_newline ();

  Printf.printf "Phase 6 — Intent Get:\n";
  test "intent_get specific field"
    {|i = intent { description: "test", author: "T" }; intent_get(i, "description")|}
    {|"test"|};
  test "intent_get missing field"
    {|i = intent { a: "1" }; intent_get(i, "b")|}
    {|Error(KeyError: "Intent field `b` not found.")|};
  test "intent_get on non-intent"
    {|intent_get(42, "x")|}
    {|Error(TypeError: "Function `intent_get` expects an Intent value as first argument.")|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Scalars:\n";
  test "explain integer kind"
    {|e = explain(42); e.kind|}
    {|"value"|};
  test "explain integer type"
    {|e = explain(42); e.type|}
    {|"Int"|};
  test "explain string"
    {|e = explain("hello"); e.type|}
    {|"String"|};
  test "explain bool"
    {|e = explain(true); e.type|}
    {|"Bool"|};
  test "explain float"
    {|e = explain(3.14); e.type|}
    {|"Float"|};
  test "explain NA"
    {|e = explain(NA); e.type|}
    {|"NA"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: NA:\n";
  test "explain NA kind"
    {|e = explain(NA); e.kind|}
    {|"value"|};
  test "explain NA type"
    {|e = explain(NA); e.type|}
    {|"NA"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Vectors:\n";
  test "explain vector kind"
    {|v = [1, 2, 3]; e = explain(v); e.kind|}
    {|"value"|};
  test "explain vector type"
    {|v = [1, 2, 3]; e = explain(v); e.type|}
    {|"List"|};
  test "explain vector length"
    {|v = [1, 2, 3]; e = explain(v); e.length|}
    "3";
  test "explain vector na_count"
    {|v = [1, NA, 3]; e = explain(v); e.na_count|}
    "1";
  print_newline ();

  Printf.printf "Phase 6 — Explain: DataFrame:\n";
  (* Create test CSV for explain tests *)
  let csv_p6 = "test_phase6.csv" in
  let oc7 = open_out csv_p6 in
  output_string oc7 "name,age,score\nAlice,30,95.5\nBob,NA,87.3\nCharlie,35,NA\n";
  close_out oc7;

  let env_p6 = Packages.init_env () in
  let env_p6 = Test_helpers.eval_setup eval_string_env env_p6 "test_explain_tests:94" (Printf.sprintf {|df = read_csv("%s")|} csv_p6) in
  test_env env_p6 "explain DataFrame kind"
    "e = explain(df); e.kind"
    {|"to_dataframe"|};
  test_env env_p6 "explain DataFrame nrow"
    "e = explain(df); e.nrow"
    "3";
  test_env env_p6 "explain DataFrame ncol"
    "e = explain(df); e.ncol"
    "3";
  test_env env_p6 "explain DataFrame storage_backend is a String"
    "e = explain(df); type(e.storage_backend)"
    {|"String"|};
  test_env env_p6 "explain DataFrame native_path_active is a Bool"
    "e = explain(df); type(e.native_path_active)"
    {|"Bool"|};
  test_env env_p6 "explain DataFrame performance_note is a String"
    "e = explain(df); type(e.performance_note)"
    {|"String"|};
  (* Check NA stats *)
  test_env env_p6 "explain DataFrame NA stats (age has 1 NA)"
    "e = explain(df); e.na_stats.age"
    "1";
  test_env env_p6 "explain DataFrame NA stats (score has 1 NA)"
    "e = explain(df); e.na_stats.score"
    "1";
  test_env env_p6 "explain DataFrame NA stats (name has 0 NAs)"
    "e = explain(df); e.na_stats.name"
    "0";
  (* Check schema *)
  test_env env_p6 "explain DataFrame schema is a List"
    "e = explain(df); type(e.schema)"
    {|"List"|};
  (* Check example rows *)
  test_env env_p6 "explain DataFrame example_rows is a List"
    "e = explain(df); type(e.example_rows)"
    {|"List"|};
  test_env env_p6 "explain DataFrame example_rows length (3 rows)"
    "e = explain(df); length(e.example_rows)"
    "3";
  test_env env_p6 "explain mutated DataFrame storage_backend is a String"
    "df_mutated = mutate(df, $score_copy = $score); e2 = explain(df_mutated); type(e2.storage_backend)"
    {|"String"|};
  test_env env_p6 "explain mutated DataFrame native_path_active is a Bool"
    "df_mutated = mutate(df, $score_copy = $score); e2 = explain(df_mutated); type(e2.native_path_active)"
    {|"Bool"|};
  (* A DataFrame whose only column is NA in every row can now stay on the
     native Arrow path via the NAColumn builder path. *)
  test_env env_p6 "explain NA-only DataFrame storage_backend"
    "df_na_only = to_dataframe([[missing: NA], [missing: NA]]); e3 = explain(df_na_only); e3.storage_backend"
    {|"native_arrow"|};
  test_env env_p6 "explain NA-only DataFrame native_path_active"
    "df_na_only = to_dataframe([[missing: NA], [missing: NA]]); e3 = explain(df_na_only); e3.native_path_active"
    "true";
  (try Sys.remove csv_p6 with _ -> ());
  print_newline ();

  Printf.printf "Phase 6 — Explain: Pipeline:\n";
  let env_p6_pipe = Test_helpers.eval_setup eval_string_env (Packages.init_env ()) "test_explain_tests:152" "p = pipeline {\n  x = 10\n  y = x + 5\n  z = y * 2\n}" in
  test_env env_p6_pipe "explain Pipeline kind"
    "e = explain(p); e.kind"
    {|"pipeline"|};
  test_env env_p6_pipe "explain Pipeline node_count"
    "e = explain(p); e.node_count"
    "3";
  print_newline ();

  Printf.printf "Phase 6 — Explain: Intent:\n";
  test "explain intent kind"
    {|i = intent { description: "test" }; e = explain(i); e.kind|}
    {|"intent"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Error:\n";
  test "explain error"
    {|e = explain(1 / 0); e.type|}
    {|"Error"|};
  test "explain error code"
    {|e = explain(1 / 0); e.error_code|}
    {|"DivisionByZero"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Functions and Lambdas:\n";
  test "explain user-defined lambda function"
    {|f = \(x: Int, y: String) x; e = explain(f); e.type|}
    {|"Function"|};
  test "explain user-defined lambda arguments count"
    {|f = \(x: Int, y: String) x; e = explain(f); length(e.arguments)|}
    {|2|};
  test "explain user-defined lambda argument name"
    {|f = \(x: Int, y: String) x; e = explain(f); get(e.arguments, 0).name|}
    {|"x"|};
  test "explain user-defined lambda argument type"
    {|f = \(x: Int, y: String) x; e = explain(f); get(e.arguments, 0).type|}
    {|"Int"|};
  test "explain user-defined lambda argument 2 type"
    {|f = \(x: Int, y: String) x; e = explain(f); get(e.arguments, 1).type|}
    {|"String"|};
  test "explain builtin function"
    {|e = explain(explain); e.type|}
    {|"Function"|};
  test "explain builtin arguments count"
    {|e = explain(explain); length(e.arguments)|}
    {|1|};
  test "explain builtin argument name"
    {|e = explain(explain); get(e.arguments, 0).name|}
    {|"x"|};
  test "explain builtin argument type"
    {|e = explain(explain); get(e.arguments, 0).type|}
    {|"Any"|};
  test "explain builtin argument default"
    {|e = explain(explain); type(get(e.arguments, 0).default)|}
    {|"NA"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Arity:\n";
  test "explain no args"
    "explain()"
    {|Error(ArityError: "Function `explain` expects 1 arguments but received 0.")|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Pipeline Integration:\n";
  test "explain in pipe"
    {|42 |> explain|}
    {|{`kind`: "value", `type`: "Int", `value`: 42}|};
  print_newline ();

  Printf.printf "Phase 6 — Functions available without imports:\n";
  test "explain available" {|type(explain(42))|}  {|"Dict"|};
  test "intent_fields available" {|i = intent { a: "1" }; type(intent_fields(i))|} {|"Dict"|};
  test "intent_get available" {|i = intent { a: "1" }; intent_get(i, "a")|} {|"1"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Foreign Meta (unbuilt node):\n";
  test "explain unbuilt node foreign_meta is NA"
    {|p_fm = pipeline { x = 1 }; e_fm = explain(p_fm.x); type(e_fm.foreign_meta)|}
    {|"NA"|};
  print_newline ();

  Printf.printf "Phase 6 — Explain: Foreign Meta (meta sidecar):\n";
  let meta_base = Filename.concat (Filename.get_temp_dir_name ()) "tlang-explain-foreign-meta" in
  (try Unix.mkdir meta_base 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let make_node_dir name =
    let dir = Filename.concat meta_base name in
    (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
    dir
  in
  let write_file path content =
    let oc = open_out path in
    Fun.protect ~finally:(fun () -> close_out_noerr oc)
      (fun () -> output_string oc content)
  in
  let fake_cn ~name ~runtime ~path ~class_ =
    { Ast.cn_name = name; cn_runtime = runtime; cn_path = path;
      cn_serializer = "default"; cn_class = class_; cn_dependencies = [];
      cn_p_exprs = None; cn_flake = None; cn_config = None }
  in
  (* R model node with a full meta sidecar *)
  let model_dir = make_node_dir "fake-r-model" in
  write_file (Filename.concat model_dir "artifact") "0123456789";
  write_file (Filename.concat model_dir "meta")
    {|{"kind":"model","class":"lm","task":"regression","n_obs":32,"n_features":2,"target":"mpg","features":["wt","hp"],"formula":"mpg ~ wt + hp","metrics":{"r_squared":0.82,"aic":150.5}}|};
  let env_fm_model =
    Ast.Env.add "fake_r_model"
      (Ast.VComputedNode (fake_cn ~name:"fake_r_model_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat model_dir "artifact") ~class_:"lm"))
      (Packages.init_env ())
  in
  test_env env_fm_model "explain foreign meta model kind"
    "explain(fake_r_model).foreign_meta.kind"
    {|"model"|};
  test_env env_fm_model "explain foreign meta model task"
    "explain(fake_r_model).foreign_meta.task"
    {|"regression"|};
  test_env env_fm_model "explain foreign meta model n_obs"
    "explain(fake_r_model).foreign_meta.n_obs"
    "32";
  test_env env_fm_model "explain foreign meta model n_features"
    "explain(fake_r_model).foreign_meta.n_features"
    "2";
  test_env env_fm_model "explain foreign meta model target"
    "explain(fake_r_model).foreign_meta.target"
    {|"mpg"|};
  test_env env_fm_model "explain foreign meta model formula (full)"
    "explain(fake_r_model).foreign_meta.formula"
    {|"mpg ~ wt + hp"|};
  test_env env_fm_model "explain foreign meta model features count"
    "length(explain(fake_r_model).foreign_meta.features)"
    "2";
  test_env env_fm_model "explain foreign meta model features preview"
    "explain(fake_r_model).foreign_meta.features_preview"
    {|"[\"wt\", \"hp\"]"|};
  test_env env_fm_model "explain foreign meta model metric"
    "explain(fake_r_model).foreign_meta.metrics.r_squared"
    "0.82";
  test_env env_fm_model "explain foreign meta artifact size"
    "explain(fake_r_model).foreign_meta.artifact_size"
    "10";
  (* DataFrame node with six columns: preview truncates, full list is kept *)
  let df_dir = make_node_dir "fake-py-frame" in
  write_file (Filename.concat df_dir "artifact") "0123456789";
  write_file (Filename.concat df_dir "meta")
    {|{"kind":"dataframe","nrow":100,"ncol":6,"features":["a","b","c","d","e","f"]}|};
  let env_fm_df =
    Ast.Env.add "fake_py_frame"
      (Ast.VComputedNode (fake_cn ~name:"fake_py_frame_foreign_meta_test" ~runtime:"Python"
        ~path:(Filename.concat df_dir "artifact") ~class_:"DataFrame"))
      (Packages.init_env ())
  in
  test_env env_fm_df "explain foreign meta frame shape"
    "explain(fake_py_frame).foreign_meta.nrow"
    "100";
  test_env env_fm_df "explain foreign meta frame features count"
    "length(explain(fake_py_frame).foreign_meta.features)"
    "6";
  test_env env_fm_df "explain foreign meta frame features preview truncates"
    "explain(fake_py_frame).foreign_meta.features_preview"
    "+3 more";
  (* Long formula: preview truncates at 80 chars, full value is kept *)
  let long_dir = make_node_dir "fake-long-formula" in
  write_file (Filename.concat long_dir "artifact") "0123456789";
  let long_formula = "y ~ " ^ String.make 100 'x' in
  write_file (Filename.concat long_dir "meta")
    (Printf.sprintf {|{"kind":"model","formula":%s}|} (Printf.sprintf "%S" long_formula));
  let env_fm_long =
    Ast.Env.add "fake_long_model"
      (Ast.VComputedNode (fake_cn ~name:"fake_long_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat long_dir "artifact") ~class_:"lm"))
      (Packages.init_env ())
  in
  test_env env_fm_long "explain foreign meta long formula keeps full text"
    "str_nchar(explain(fake_long_model).foreign_meta.formula)"
    "104";
  test_env env_fm_long "explain foreign meta long formula preview truncates"
    "explain(fake_long_model).foreign_meta.formula_preview"
    "...";
  (* Artifact without a meta sidecar: only artifact_size is reported *)
  let bare_dir = make_node_dir "fake-bare-node" in
  write_file (Filename.concat bare_dir "artifact") "0123456789";
  let env_fm_bare =
    Ast.Env.add "fake_bare_node"
      (Ast.VComputedNode (fake_cn ~name:"fake_bare_foreign_meta_test" ~runtime:"Julia"
        ~path:(Filename.concat bare_dir "artifact") ~class_:"DataFrame"))
      (Packages.init_env ())
  in
  test_env env_fm_bare "explain foreign meta without sidecar keeps artifact size"
    "explain(fake_bare_node).foreign_meta.artifact_size"
    "10";
  (* Time-series model node: order, seasonal_order, loglik/sigma2 metrics *)
  let ts_dir = make_node_dir "fake-ts-model" in
  write_file (Filename.concat ts_dir "artifact") "0123456789";
  write_file (Filename.concat ts_dir "meta")
    {|{"kind":"model","class":"Arima","task":"time_series","n_obs":131,"order":[1,1,1],"seasonal_order":[1,1,1,12],"n_features":4,"features":["ar1","ma1","sar1","sma1"],"metrics":{"loglik":-506.1498,"sigma2":130.7678,"aic":1022.2996}}|};
  let env_fm_ts =
    Ast.Env.add "fake_ts_model"
      (Ast.VComputedNode (fake_cn ~name:"fake_ts_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat ts_dir "artifact") ~class_:"Arima"))
      (Packages.init_env ())
  in
  test_env env_fm_ts "explain foreign meta time series task"
    "explain(fake_ts_model).foreign_meta.task"
    {|"time_series"|};
  test_env env_fm_ts "explain foreign meta time series order length"
    "length(explain(fake_ts_model).foreign_meta.order)"
    "3";
  test_env env_fm_ts "explain foreign meta time series order values"
    "get(explain(fake_ts_model).foreign_meta.order, 0) + get(explain(fake_ts_model).foreign_meta.order, 2)"
    "2";
  test_env env_fm_ts "explain foreign meta time series seasonal order length"
    "length(explain(fake_ts_model).foreign_meta.seasonal_order)"
    "4";
  test_env env_fm_ts "explain foreign meta time series loglik"
    "explain(fake_ts_model).foreign_meta.metrics.loglik"
    "-506.1498";
  (* Forest + boosted-tree nodes: n_trees / n_rounds *)
  let forest_dir = make_node_dir "fake-forest" in
  write_file (Filename.concat forest_dir "artifact") "0123456789";
  write_file (Filename.concat forest_dir "meta")
    {|{"kind":"model","class":"randomForest.formula","task":"classification","n_trees":20,"n_obs":150,"n_features":4,"metrics":{"oob_error":0.0467}}|};
  let env_fm_forest =
    Ast.Env.add "fake_forest"
      (Ast.VComputedNode (fake_cn ~name:"fake_forest_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat forest_dir "artifact") ~class_:"randomForest.formula"))
      (Packages.init_env ())
  in
  test_env env_fm_forest "explain foreign meta forest task"
    "explain(fake_forest).foreign_meta.task"
    {|"classification"|};
  test_env env_fm_forest "explain foreign meta forest tree count"
    "explain(fake_forest).foreign_meta.n_trees"
    "20";
  test_env env_fm_forest "explain foreign meta forest oob error"
    "explain(fake_forest).foreign_meta.metrics.oob_error"
    "0.0467";
  let xgb_dir = make_node_dir "fake-xgb" in
  write_file (Filename.concat xgb_dir "artifact") "0123456789";
  write_file (Filename.concat xgb_dir "meta")
    {|{"kind":"model","class":"Booster","task":"classification","n_rounds":5,"n_features":2}|};
  let env_fm_xgb =
    Ast.Env.add "fake_xgb"
      (Ast.VComputedNode (fake_cn ~name:"fake_xgb_foreign_meta_test" ~runtime:"Python"
        ~path:(Filename.concat xgb_dir "artifact") ~class_:"Booster"))
      (Packages.init_env ())
  in
  test_env env_fm_xgb "explain foreign meta xgboost round count"
    "explain(fake_xgb).foreign_meta.n_rounds"
    "5";
  test_env env_fm_xgb "explain foreign meta xgboost task"
    "explain(fake_xgb).foreign_meta.task"
    {|"classification"|};
  (* Boosted trees, clustering, and dim-reduction branches *)
  let lgb_dir = make_node_dir "fake-lgb" in
  write_file (Filename.concat lgb_dir "artifact") "0123456789";
  write_file (Filename.concat lgb_dir "meta")
    {|{"kind":"model","class":"lgb.Booster","task":"classification","n_rounds":5}|};
  let env_fm_lgb =
    Ast.Env.add "fake_lgb"
      (Ast.VComputedNode (fake_cn ~name:"fake_lgb_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat lgb_dir "artifact") ~class_:"lgb.Booster"))
      (Packages.init_env ())
  in
  test_env env_fm_lgb "explain foreign meta lightgbm rounds"
    "explain(fake_lgb).foreign_meta.n_rounds"
    "5";
  test_env env_fm_lgb "explain foreign meta lightgbm task"
    "explain(fake_lgb).foreign_meta.task"
    {|"classification"|};
  let km_dir = make_node_dir "fake-kmeans" in
  write_file (Filename.concat km_dir "artifact") "0123456789";
  write_file (Filename.concat km_dir "meta")
    {|{"kind":"model","class":"kmeans","task":"clustering","n_clusters":3,"n_obs":32,"metrics":{"var_explained":0.8535}}|};
  let env_fm_km =
    Ast.Env.add "fake_km"
      (Ast.VComputedNode (fake_cn ~name:"fake_km_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat km_dir "artifact") ~class_:"kmeans"))
      (Packages.init_env ())
  in
  test_env env_fm_km "explain foreign meta kmeans clusters"
    "explain(fake_km).foreign_meta.n_clusters"
    "3";
  test_env env_fm_km "explain foreign meta kmeans variance"
    "explain(fake_km).foreign_meta.metrics.var_explained"
    "0.8535";
  let hc_dir = make_node_dir "fake-hclust" in
  write_file (Filename.concat hc_dir "artifact") "0123456789";
  write_file (Filename.concat hc_dir "meta")
    {|{"kind":"model","class":"hclust","task":"clustering","method":"complete","n_obs":32}|};
  let env_fm_hc =
    Ast.Env.add "fake_hc"
      (Ast.VComputedNode (fake_cn ~name:"fake_hc_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat hc_dir "artifact") ~class_:"hclust"))
      (Packages.init_env ())
  in
  test_env env_fm_hc "explain foreign meta hclust method"
    "explain(fake_hc).foreign_meta.method"
    {|"complete"|};
  let pc_dir = make_node_dir "fake-pca" in
  write_file (Filename.concat pc_dir "artifact") "0123456789";
  write_file (Filename.concat pc_dir "meta")
    {|{"kind":"model","task":"dim_reduction","n_components":2,"n_features":2,"metrics":{"var_first":1.0}}|};
  let env_fm_pc =
    Ast.Env.add "fake_pca"
      (Ast.VComputedNode (fake_cn ~name:"fake_pca_foreign_meta_test" ~runtime:"Python"
        ~path:(Filename.concat pc_dir "artifact") ~class_:"PCA"))
      (Packages.init_env ())
  in
  test_env env_fm_pc "explain foreign meta pca components"
    "explain(fake_pca).foreign_meta.n_components"
    "2";
  test_env env_fm_pc "explain foreign meta pca task"
    "explain(fake_pca).foreign_meta.task"
    {|"dim_reduction"|};
  print_newline ()
