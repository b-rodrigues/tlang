let run_tests pass_count fail_count failures _eval_string eval_string_env test test_env _test_equal =
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
  (* Unique per-process scratch dir, removed at the end of the section. *)
  let meta_base =
    Filename.concat (Filename.get_temp_dir_name ())
      ("tlang-explain-foreign-meta-" ^ string_of_int (Unix.getpid ()))
  in
  (try Unix.mkdir meta_base 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let rec rm_rf path =
    (try
       if Sys.is_directory path then begin
         Array.iter (fun e ->
           if e <> "." && e <> ".." then rm_rf (Filename.concat path e)
         ) (Sys.readdir path);
         Unix.rmdir path
       end else Sys.remove path
     with _ -> ())
  in
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
    {|{"kind":"dataframe","dimensions":[100,6],"features":["a","b","c","d","e","f"]}|};
  let env_fm_df =
    Ast.Env.add "fake_py_frame"
      (Ast.VComputedNode (fake_cn ~name:"fake_py_frame_foreign_meta_test" ~runtime:"Python"
        ~path:(Filename.concat df_dir "artifact") ~class_:"DataFrame"))
      (Packages.init_env ())
  in
  test_env env_fm_df "explain foreign meta frame dimensions"
    "get(explain(fake_py_frame).foreign_meta.dimensions, 0)"
    "100";
  test_env env_fm_df "explain foreign meta frame dimensions rank"
    "length(explain(fake_py_frame).foreign_meta.dimensions)"
    "2";
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
  let jlkm_dir = make_node_dir "fake-jlkm" in
  write_file (Filename.concat jlkm_dir "artifact") "0123456789";
  write_file (Filename.concat jlkm_dir "meta")
    {|{"kind":"model","class":"KmeansResult","task":"clustering","n_clusters":2,"n_obs":4,"n_features":2,"metrics":{"totalcost":4.0}}|};
  let env_fm_jlkm =
    Ast.Env.add "fake_jlkm"
      (Ast.VComputedNode (fake_cn ~name:"fake_jlkm_foreign_meta_test" ~runtime:"Julia"
        ~path:(Filename.concat jlkm_dir "artifact") ~class_:"KmeansResult"))
      (Packages.init_env ())
  in
  test_env env_fm_jlkm "explain foreign meta julia kmeans task"
    "explain(fake_jlkm).foreign_meta.task"
    {|"clustering"|};
  test_env env_fm_jlkm "explain foreign meta julia kmeans cost"
    "explain(fake_jlkm).foreign_meta.metrics.totalcost"
    "4";
  (* Mixed-effects model node: groups dict *)
  let mix_dir = make_node_dir "fake-mixed" in
  write_file (Filename.concat mix_dir "artifact") "0123456789";
  write_file (Filename.concat mix_dir "meta")
    {|{"kind":"model","class":"lmerMod","task":"regression","n_obs":180,"formula":"Reaction ~ Days + (Days | Subject)","target":"Reaction","n_features":1,"n_groups":18,"groups":{"Subject":18},"metrics":{"loglik":-871.81}}|};
  let env_fm_mix =
    Ast.Env.add "fake_mixed"
      (Ast.VComputedNode (fake_cn ~name:"fake_mixed_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat mix_dir "artifact") ~class_:"lmerMod"))
      (Packages.init_env ())
  in
  test_env env_fm_mix "explain foreign meta mixed groups"
    "explain(fake_mixed).foreign_meta.groups.Subject"
    "18";
  test_env env_fm_mix "explain foreign meta mixed group count"
    "explain(fake_mixed).foreign_meta.n_groups"
    "18";
  test_env env_fm_mix "explain foreign meta mixed formula keeps random effects"
    "explain(fake_mixed).foreign_meta.formula"
    {|"Reaction ~ Days + (Days | Subject)"|};
  (* Discriminant, test, mixture, and data-container branches *)
  let lda_dir = make_node_dir "fake-lda" in
  write_file (Filename.concat lda_dir "artifact") "0123456789";
  write_file (Filename.concat lda_dir "meta")
    {|{"kind":"model","class":"lda","task":"classification","n_obs":150,"n_features":4,"metrics":{"n_classes":3}}|};
  let env_fm_lda =
    Ast.Env.add "fake_lda"
      (Ast.VComputedNode (fake_cn ~name:"fake_lda_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat lda_dir "artifact") ~class_:"lda"))
      (Packages.init_env ())
  in
  test_env env_fm_lda "explain foreign meta lda classes"
    "explain(fake_lda).foreign_meta.metrics.n_classes"
    "3";
  let ht_dir = make_node_dir "fake-htest" in
  write_file (Filename.concat ht_dir "artifact") "0123456789";
  write_file (Filename.concat ht_dir "meta")
    {|{"kind":"test","class":"htest","method":"Welch Two Sample t-test","metrics":{"p_value":0.0014}}|};
  let env_fm_ht =
    Ast.Env.add "fake_ht"
      (Ast.VComputedNode (fake_cn ~name:"fake_ht_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat ht_dir "artifact") ~class_:"htest"))
      (Packages.init_env ())
  in
  test_env env_fm_ht "explain foreign meta htest kind"
    "explain(fake_ht).foreign_meta.kind"
    {|"test"|};
  test_env env_fm_ht "explain foreign meta htest method"
    "explain(fake_ht).foreign_meta.method"
    {|"Welch Two Sample t-test"|};
  let gmm_dir = make_node_dir "fake-gmm" in
  write_file (Filename.concat gmm_dir "artifact") "0123456789";
  write_file (Filename.concat gmm_dir "meta")
    {|{"kind":"model","class":"GaussianMixture","task":"density","n_features":1,"n_components":2,"metrics":{"lower_bound":0.02}}|};
  let env_fm_gmm =
    Ast.Env.add "fake_gmm"
      (Ast.VComputedNode (fake_cn ~name:"fake_gmm_foreign_meta_test" ~runtime:"Python"
        ~path:(Filename.concat gmm_dir "artifact") ~class_:"GaussianMixture"))
      (Packages.init_env ())
  in
  test_env env_fm_gmm "explain foreign meta mixture task"
    "explain(fake_gmm).foreign_meta.task"
    {|"density"|};
  test_env env_fm_gmm "explain foreign meta mixture bound"
    "explain(fake_gmm).foreign_meta.metrics.lower_bound"
    "0.02";
  let dm_dir = make_node_dir "fake-dm" in
  write_file (Filename.concat dm_dir "artifact") "0123456789";
  write_file (Filename.concat dm_dir "meta")
    {|{"kind":"data","class":"DMatrix","dimensions":[6,1]}|};
  let env_fm_dm =
    Ast.Env.add "fake_dm"
      (Ast.VComputedNode (fake_cn ~name:"fake_dm_foreign_meta_test" ~runtime:"Python"
        ~path:(Filename.concat dm_dir "artifact") ~class_:"DMatrix"))
      (Packages.init_env ())
  in
  test_env env_fm_dm "explain foreign meta data container kind"
    "explain(fake_dm).foreign_meta.kind"
    {|"data"|};
  test_env env_fm_dm "explain foreign meta data container dimensions"
    "get(explain(fake_dm).foreign_meta.dimensions, 0)"
    "6";
  let tr_dir = make_node_dir "fake-transformer" in
  write_file (Filename.concat tr_dir "artifact") "0123456789";
  write_file (Filename.concat tr_dir "meta")
    {|{"kind":"transformer","class":"StandardScaler","n_features":1}|};
  let env_fm_tr =
    Ast.Env.add "fake_tr"
      (Ast.VComputedNode (fake_cn ~name:"fake_tr_foreign_meta_test" ~runtime:"Python"
        ~path:(Filename.concat tr_dir "artifact") ~class_:"StandardScaler"))
      (Packages.init_env ())
  in
  test_env env_fm_tr "explain foreign meta transformer kind"
    "explain(fake_tr).foreign_meta.kind"
    {|"transformer"|};
  let fac_dir = make_node_dir "fake-factor" in
  write_file (Filename.concat fac_dir "artifact") "0123456789";
  write_file (Filename.concat fac_dir "meta")
    {|{"kind":"factor","class":"factor","n_levels":2,"levels":["a","b"]}|};
  let env_fm_fac =
    Ast.Env.add "fake_fac"
      (Ast.VComputedNode (fake_cn ~name:"fake_fac_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat fac_dir "artifact") ~class_:"factor"))
      (Packages.init_env ())
  in
  test_env env_fm_fac "explain foreign meta factor levels"
    "explain(fake_fac).foreign_meta.levels_preview"
    {|"[\"a\", \"b\"]"|};
  test_env env_fm_fac "explain foreign meta factor level count"
    "explain(fake_fac).foreign_meta.n_levels"
    "2";
  let ts_dir = make_node_dir "fake-tsobj" in
  write_file (Filename.concat ts_dir "artifact") "0123456789";
  write_file (Filename.concat ts_dir "meta")
    {|{"kind":"series","class":"ts","n_obs":144,"metrics":{"period":12},"start":"1949-1","end":"1960-12"}|};
  let env_fm_tsobj =
    Ast.Env.add "fake_tsobj"
      (Ast.VComputedNode (fake_cn ~name:"fake_tsobj_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat ts_dir "artifact") ~class_:"ts"))
      (Packages.init_env ())
  in
  test_env env_fm_tsobj "explain foreign meta series range"
    "explain(fake_tsobj).foreign_meta.start"
    {|"1949-1"|};
  test_env env_fm_tsobj "explain foreign meta series period"
    "explain(fake_tsobj).foreign_meta.metrics.period"
    "12";
  let surv_dir = make_node_dir "fake-survfit" in
  write_file (Filename.concat surv_dir "artifact") "0123456789";
  write_file (Filename.concat surv_dir "meta")
    {|{"kind":"model","class":"survfit","task":"survival","n_obs":228,"n_groups":2}|};
  let env_fm_surv =
    Ast.Env.add "fake_surv"
      (Ast.VComputedNode (fake_cn ~name:"fake_surv_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat surv_dir "artifact") ~class_:"survfit"))
      (Packages.init_env ())
  in
  test_env env_fm_surv "explain foreign meta survfit task"
    "explain(fake_surv).foreign_meta.task"
    {|"survival"|};
  test_env env_fm_surv "explain foreign meta survfit groups"
    "explain(fake_surv).foreign_meta.n_groups"
    "2";
  let rpart_dir = make_node_dir "fake-rpart" in
  write_file (Filename.concat rpart_dir "artifact") "0123456789";
  write_file (Filename.concat rpart_dir "meta")
    {|{"kind":"model","class":"rpart","n_nodes":5,"n_features":2}|};
  let env_fm_rpart =
    Ast.Env.add "fake_rpart"
      (Ast.VComputedNode (fake_cn ~name:"fake_rpart_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat rpart_dir "artifact") ~class_:"rpart"))
      (Packages.init_env ())
  in
  test_env env_fm_rpart "explain foreign meta rpart nodes"
    "explain(fake_rpart).foreign_meta.n_nodes"
    "5";
  let dens_dir = make_node_dir "fake-density" in
  write_file (Filename.concat dens_dir "artifact") "0123456789";
  write_file (Filename.concat dens_dir "meta")
    {|{"kind":"distribution","class":"density","n_obs":32,"metrics":{"bw":2.476}}|};
  let env_fm_dens =
    Ast.Env.add "fake_dens"
      (Ast.VComputedNode (fake_cn ~name:"fake_dens_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat dens_dir "artifact") ~class_:"density"))
      (Packages.init_env ())
  in
  test_env env_fm_dens "explain foreign meta density kind"
    "explain(fake_dens).foreign_meta.kind"
    {|"distribution"|};
  test_env env_fm_dens "explain foreign meta density bw"
    "explain(fake_dens).foreign_meta.metrics.bw"
    "2.476";
  let acf_dir = make_node_dir "fake-acf" in
  write_file (Filename.concat acf_dir "artifact") "0123456789";
  write_file (Filename.concat acf_dir "meta")
    {|{"kind":"model","class":"acf","task":"time_series","n_obs":144,"method":"correlation"}|};
  let env_fm_acf =
    Ast.Env.add "fake_acf"
      (Ast.VComputedNode (fake_cn ~name:"fake_acf_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat acf_dir "artifact") ~class_:"acf"))
      (Packages.init_env ())
  in
  test_env env_fm_acf "explain foreign meta acf task"
    "explain(fake_acf).foreign_meta.task"
    {|"time_series"|};
  test_env env_fm_acf "explain foreign meta acf method"
    "explain(fake_acf).foreign_meta.method"
    {|"correlation"|};
  let spl_dir = make_node_dir "fake-spline" in
  write_file (Filename.concat spl_dir "artifact") "0123456789";
  write_file (Filename.concat spl_dir "meta")
    {|{"kind":"model","class":"smooth.spline","task":"regression","n_obs":32}|};
  let env_fm_spl =
    Ast.Env.add "fake_spl"
      (Ast.VComputedNode (fake_cn ~name:"fake_spl_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat spl_dir "artifact") ~class_:"smooth.spline"))
      (Packages.init_env ())
  in
  test_env env_fm_spl "explain foreign meta spline task"
    "explain(fake_spl).foreign_meta.task"
    {|"regression"|};
  let ecf_dir = make_node_dir "fake-ecdf" in
  write_file (Filename.concat ecf_dir "artifact") "0123456789";
  write_file (Filename.concat ecf_dir "meta")
    {|{"kind":"distribution","class":"ecdf","n_obs":32}|};
  let env_fm_ecf =
    Ast.Env.add "fake_ecf"
      (Ast.VComputedNode (fake_cn ~name:"fake_ecf_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat ecf_dir "artifact") ~class_:"ecdf"))
      (Packages.init_env ())
  in
  test_env env_fm_ecf "explain foreign meta ecdf kind"
    "explain(fake_ecf).foreign_meta.kind"
    {|"distribution"|};
  let tbl_dir = make_node_dir "fake-table" in
  write_file (Filename.concat tbl_dir "artifact") "0123456789";
  write_file (Filename.concat tbl_dir "meta")
    {|{"kind":"table","class":"table","dimensions":[3,3],"dtype":"integer"}|};
  let env_fm_tbl =
    Ast.Env.add "fake_tbl"
      (Ast.VComputedNode (fake_cn ~name:"fake_tbl_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat tbl_dir "artifact") ~class_:"table"))
      (Packages.init_env ())
  in
  test_env env_fm_tbl "explain foreign meta table kind"
    "explain(fake_tbl).foreign_meta.kind"
    {|"table"|};
  test_env env_fm_tbl "explain foreign meta table dimensions"
    "get(explain(fake_tbl).foreign_meta.dimensions, 0)"
    "3";
  let pam_dir = make_node_dir "fake-pam" in
  write_file (Filename.concat pam_dir "artifact") "0123456789";
  write_file (Filename.concat pam_dir "meta")
    {|{"kind":"model","class":"pam","task":"clustering","n_clusters":4,"n_obs":75}|};
  let env_fm_pam =
    Ast.Env.add "fake_pam"
      (Ast.VComputedNode (fake_cn ~name:"fake_pam_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat pam_dir "artifact") ~class_:"pam"))
      (Packages.init_env ())
  in
  test_env env_fm_pam "explain foreign meta pam clusters"
    "explain(fake_pam).foreign_meta.n_clusters"
    "4";
  let stl_dir = make_node_dir "fake-stl" in
  write_file (Filename.concat stl_dir "artifact") "0123456789";
  write_file (Filename.concat stl_dir "meta")
    {|{"kind":"model","class":"stl","task":"time_series","n_obs":144,"n_features":3,"metrics":{"period":12}}|};
  let env_fm_stl =
    Ast.Env.add "fake_stl"
      (Ast.VComputedNode (fake_cn ~name:"fake_stl_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat stl_dir "artifact") ~class_:"stl"))
      (Packages.init_env ())
  in
  test_env env_fm_stl "explain foreign meta stl task"
    "explain(fake_stl).foreign_meta.task"
    {|"time_series"|};
  test_env env_fm_stl "explain foreign meta stl period"
    "explain(fake_stl).foreign_meta.metrics.period"
    "12";
  let cox_dir = make_node_dir "fake-cox" in
  write_file (Filename.concat cox_dir "artifact") "0123456789";
  write_file (Filename.concat cox_dir "meta")
    {|{"kind":"model","class":"coxph","task":"survival","n_obs":228,"n_features":2,"metrics":{"concordance":0.6028,"n_events":165}}|};
  let env_fm_cox =
    Ast.Env.add "fake_cox"
      (Ast.VComputedNode (fake_cn ~name:"fake_cox_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat cox_dir "artifact") ~class_:"coxph"))
      (Packages.init_env ())
  in
  test_env env_fm_cox "explain foreign meta coxph task"
    "explain(fake_cox).foreign_meta.task"
    {|"survival"|};
  test_env env_fm_cox "explain foreign meta coxph events"
    "explain(fake_cox).foreign_meta.metrics.n_events"
    "165";
  let rank_dir = make_node_dir "fake-ranker" in
  write_file (Filename.concat rank_dir "artifact") "0123456789";
  write_file (Filename.concat rank_dir "meta")
    {|{"kind":"model","class":"XGBRanker","task":"ranking","n_rounds":3,"n_features":3}|};
  let env_fm_rank =
    Ast.Env.add "fake_rank"
      (Ast.VComputedNode (fake_cn ~name:"fake_rank_foreign_meta_test" ~runtime:"Python"
        ~path:(Filename.concat rank_dir "artifact") ~class_:"XGBRanker"))
      (Packages.init_env ())
  in
  test_env env_fm_rank "explain foreign meta ranker task"
    "explain(fake_rank).foreign_meta.task"
    {|"ranking"|};
  test_env env_fm_rank "explain foreign meta ranker rounds"
    "explain(fake_rank).foreign_meta.n_rounds"
    "3";
  let fz_dir = make_node_dir "fake-frozen" in
  write_file (Filename.concat fz_dir "artifact") "0123456789";
  write_file (Filename.concat fz_dir "meta")
    {|{"kind":"distribution","class":"rv_continuous_frozen","method":"norm","metrics":{"mean":0.0,"std":1.0}}|};
  let env_fm_fz =
    Ast.Env.add "fake_fz"
      (Ast.VComputedNode (fake_cn ~name:"fake_fz_foreign_meta_test" ~runtime:"Python"
        ~path:(Filename.concat fz_dir "artifact") ~class_:"rv_continuous_frozen"))
      (Packages.init_env ())
  in
  test_env env_fm_fz "explain foreign meta frozen dist kind"
    "explain(fake_fz).foreign_meta.kind"
    {|"distribution"|};
  test_env env_fm_fz "explain foreign meta frozen dist name"
    "explain(fake_fz).foreign_meta.method"
    {|"norm"|};
  (* Pipeline lineage: direct children per node. *)
  test "explain pipeline node children"
    {|p_lin = pipeline { x = 10; y = x + 5; z = x + y }; e_lin = explain(p_lin); get(get(e_lin.nodes, 0).children, 0)|}
    {|"y"|};
  test "explain pipeline node children count"
    {|p_lin = pipeline { x = 10; y = x + 5; z = x + y }; e_lin = explain(p_lin); length(get(e_lin.nodes, 0).children)|}
    "2";
  test "explain pipeline leaf has no children"
    {|p_lin = pipeline { x = 10; y = x + 5; z = x + y }; e_lin = explain(p_lin); length(get(e_lin.nodes, 2).children)|}
    "0";
  (* Pipeline lineage: transitive ancestors and descendants. *)
  test "explain pipeline transitive ancestors"
    {|p_ch = pipeline { a = 1; b = a + 1; c = b + 1 }; e_ch = explain(p_ch); get(get(e_ch.nodes, 2).ancestors, 1)|}
    {|"a"|};
  test "explain pipeline transitive ancestors count"
    {|p_ch = pipeline { a = 1; b = a + 1; c = b + 1 }; e_ch = explain(p_ch); length(get(e_ch.nodes, 2).ancestors)|}
    "2";
  test "explain pipeline transitive descendants"
    {|p_ch = pipeline { a = 1; b = a + 1; c = b + 1 }; e_ch = explain(p_ch); get(get(e_ch.nodes, 0).descendants, 1)|}
    {|"c"|};
  test "explain pipeline root has no ancestors"
    {|p_ch = pipeline { a = 1; b = a + 1; c = b + 1 }; e_ch = explain(p_ch); length(get(e_ch.nodes, 0).ancestors)|}
    "0";
  test "explain pipeline leaf has no descendants"
    {|p_ch = pipeline { a = 1; b = a + 1; c = b + 1 }; e_ch = explain(p_ch); length(get(e_ch.nodes, 2).descendants)|}
    "0";
  (* Julia PCA and statespace nodes share the same schema keys *)
  let jlpc_dir = make_node_dir "fake-jlpca" in
  write_file (Filename.concat jlpc_dir "artifact") "0123456789";
  write_file (Filename.concat jlpc_dir "meta")
    {|{"kind":"model","class":"PCA{Float64}","task":"dim_reduction","n_features":2,"n_components":1,"metrics":{"var_first":1.0}}|};
  let env_fm_jlpc =
    Ast.Env.add "fake_jlpca"
      (Ast.VComputedNode (fake_cn ~name:"fake_jlpca_foreign_meta_test" ~runtime:"Julia"
        ~path:(Filename.concat jlpc_dir "artifact") ~class_:"PCA{Float64}"))
      (Packages.init_env ())
  in
  test_env env_fm_jlpc "explain foreign meta julia pca task"
    "explain(fake_jlpca).foreign_meta.task"
    {|"dim_reduction"|};
  test_env env_fm_jlpc "explain foreign meta julia pca components"
    "explain(fake_jlpca).foreign_meta.n_components"
    "1";
  (* Matrix / array / vector shapes across runtimes *)
  let mat_dir = make_node_dir "fake-mat" in
  write_file (Filename.concat mat_dir "artifact") "0123456789";
  write_file (Filename.concat mat_dir "meta")
    {|{"kind":"matrix","class":"matrix","dimensions":[4,3],"dtype":"integer"}|};
  let env_fm_mat =
    Ast.Env.add "fake_mat"
      (Ast.VComputedNode (fake_cn ~name:"fake_mat_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat mat_dir "artifact") ~class_:"matrix"))
      (Packages.init_env ())
  in
  test_env env_fm_mat "explain foreign meta matrix dimensions"
    "get(explain(fake_mat).foreign_meta.dimensions, 1)"
    "3";
  test_env env_fm_mat "explain foreign meta matrix dtype"
    "explain(fake_mat).foreign_meta.dtype"
    {|"integer"|};
  let arr_dir = make_node_dir "fake-arr" in
  write_file (Filename.concat arr_dir "artifact") "0123456789";
  write_file (Filename.concat arr_dir "meta")
    {|{"kind":"array","dimensions":[2,2,2],"dtype":"float64"}|};
  let env_fm_arr =
    Ast.Env.add "fake_arr"
      (Ast.VComputedNode (fake_cn ~name:"fake_arr_foreign_meta_test" ~runtime:"Python"
        ~path:(Filename.concat arr_dir "artifact") ~class_:"ndarray"))
      (Packages.init_env ())
  in
  test_env env_fm_arr "explain foreign meta array kind"
    "explain(fake_arr).foreign_meta.kind"
    {|"array"|};
  test_env env_fm_arr "explain foreign meta array dimensions rank"
    "length(explain(fake_arr).foreign_meta.dimensions)"
    "3";
  let vec_dir = make_node_dir "fake-vec" in
  write_file (Filename.concat vec_dir "artifact") "0123456789";
  write_file (Filename.concat vec_dir "meta")
    {|{"kind":"vector","class":"Vector{Int64}","dimensions":[3],"dtype":"Int64"}|};
  let env_fm_vec =
    Ast.Env.add "fake_vec"
      (Ast.VComputedNode (fake_cn ~name:"fake_vec_foreign_meta_test" ~runtime:"Julia"
        ~path:(Filename.concat vec_dir "artifact") ~class_:"Vector{Int64}"))
      (Packages.init_env ())
  in
  test_env env_fm_vec "explain foreign meta vector dimensions"
    "get(explain(fake_vec).foreign_meta.dimensions, 0)"
    "3";
  test_env env_fm_vec "explain foreign meta vector dtype"
    "explain(fake_vec).foreign_meta.dtype"
    {|"Int64"|};
  (* Degraded inputs never crash: malformed JSON, non-object top level,
     oversize files, and non-numeric metrics. The artifact size is still
     reported whenever the artifact file exists. *)
  let bad_dir = make_node_dir "fake-bad" in
  write_file (Filename.concat bad_dir "artifact") "0123456789";
  write_file (Filename.concat bad_dir "meta") "{oops";
  let env_fm_bad =
    Ast.Env.add "fake_bad"
      (Ast.VComputedNode (fake_cn ~name:"fake_bad_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat bad_dir "artifact") ~class_:"lm"))
      (Packages.init_env ())
  in
  test_env env_fm_bad "explain foreign meta malformed json degrades gracefully"
    "explain(fake_bad).foreign_meta.artifact_size"
    "10";
  let arr2_dir = make_node_dir "fake-arr2" in
  write_file (Filename.concat arr2_dir "artifact") "0123456789";
  write_file (Filename.concat arr2_dir "meta") "[1, 2]";
  let env_fm_arr2 =
    Ast.Env.add "fake_arr2"
      (Ast.VComputedNode (fake_cn ~name:"fake_arr2_foreign_meta_test" ~runtime:"Python"
        ~path:(Filename.concat arr2_dir "artifact") ~class_:"ndarray"))
      (Packages.init_env ())
  in
  test_env env_fm_arr2 "explain foreign meta non-object top level degrades gracefully"
    "explain(fake_arr2).foreign_meta.artifact_size"
    "10";
  let big_dir = make_node_dir "fake-big" in
  write_file (Filename.concat big_dir "artifact") "0123456789";
  write_file (Filename.concat big_dir "meta")
    ("{\"kind\":\"model\"" ^ String.make 2000000 ' ' ^ "}");
  let env_fm_big =
    Ast.Env.add "fake_big"
      (Ast.VComputedNode (fake_cn ~name:"fake_big_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat big_dir "artifact") ~class_:"lm"))
      (Packages.init_env ())
  in
  test_env env_fm_big "explain foreign meta oversize file degrades gracefully"
    "explain(fake_big).foreign_meta.artifact_size"
    "10";
  let strm_dir = make_node_dir "fake-strmetric" in
  write_file (Filename.concat strm_dir "artifact") "0123456789";
  write_file (Filename.concat strm_dir "meta")
    {|{"kind":"model","metrics":{"note":"hi","aic":5.0}}|};
  let env_fm_strm =
    Ast.Env.add "fake_strm"
      (Ast.VComputedNode (fake_cn ~name:"fake_strm_foreign_meta_test" ~runtime:"R"
        ~path:(Filename.concat strm_dir "artifact") ~class_:"lm"))
      (Packages.init_env ())
  in
  test_env env_fm_strm "explain foreign meta keeps numeric metrics"
    "explain(fake_strm).foreign_meta.metrics.aic"
    "5";
  test_env env_fm_strm "explain foreign meta drops string metrics"
    "length(explain(fake_strm).foreign_meta.metrics)"
    "1";
  (* Non-foreign runtimes never get foreign_meta, even with a sidecar. *)
  let t_dir = make_node_dir "fake-tnode" in
  write_file (Filename.concat t_dir "artifact") "0123456789";
  write_file (Filename.concat t_dir "meta")
    {|{"kind":"model","task":"regression"}|};
  let env_fm_t =
    Ast.Env.add "fake_tnode"
      (Ast.VComputedNode (fake_cn ~name:"fake_t_foreign_meta_test" ~runtime:"T"
        ~path:(Filename.concat t_dir "artifact") ~class_:"Int"))
      (Packages.init_env ())
  in
  test_env env_fm_t "explain foreign meta gated on foreign runtimes"
    "type(explain(fake_tnode).foreign_meta)"
    {|"NA"|};
  rm_rf meta_base;
  print_newline ();

  Printf.printf "Phase 6 — Explain: Golden Runtime Probes:\n";
  (* These execute the real r_save_meta / py_save_meta / jl_save_meta
     helpers extracted from src/pipeline/nix_emit_node.ml against fixed
     fixtures. Runtimes missing from PATH skip with a passing note. *)
  let shell_out cmd =
    try
      let ic = Unix.open_process_in cmd in
      let buf = Buffer.create 256 in
      (try while true do Buffer.add_char buf (input_char ic) done
       with End_of_file -> ());
      let _ = Unix.close_process_in ic in
      Buffer.contents buf
    with _ -> ""
  in
  let has_bin name =
    let out = shell_out (Printf.sprintf "command -v %s 2>/dev/null" name) in
    String.trim out <> ""
  in
  let contains hay needle =
    let h = String.length hay and n = String.length needle in
    n = 0 ||
    (let rec loop i =
       i + n <= h && (String.sub hay i n = needle || loop (i + 1))
     in loop 0)
  in
  let check_golden name cond =
    if cond then begin
      incr pass_count;
      Printf.printf "  SUCCESS %s\n" name
    end else begin
      incr fail_count;
      let msg = Printf.sprintf "  FAILURE %s\n" name in
      failures := msg :: !failures;
      Printf.printf "%s" msg
    end
  in
  let emit_src =
    let cands = ["src/pipeline/nix_emit_node.ml";
                 "../src/pipeline/nix_emit_node.ml";
                 "../../src/pipeline/nix_emit_node.ml"] in
    List.find_opt Sys.file_exists cands
  in
  let extract_fn ?(keep_end = true) start_marker end_pred =
    match emit_src with
    | None -> None
    | Some path ->
        (try
           let ic = open_in path in
           Fun.protect ~finally:(fun () -> close_in_noerr ic)
             (fun () ->
               let buf = Buffer.create 4096 in
               let rec skip () =
                 match (try Some (input_line ic) with End_of_file -> None) with
                 | None -> None
                 | Some line ->
                     if line = start_marker then (Buffer.add_string buf (line ^ "\n"); take ())
                     else skip ()
               and take () =
                 match (try Some (input_line ic) with End_of_file -> None) with
                 | None -> Some (Buffer.contents buf)
                 | Some line ->
                     if end_pred line then begin
                       if keep_end then Buffer.add_string buf (line ^ "\n");
                       Some (Buffer.contents buf)
                     end else begin
                       Buffer.add_string buf (line ^ "\n");
                       take ()
                     end
               in
               skip ())
         with _ -> None)
  in
  let golden_skips = ref 0 in
  let skip_golden name reason =
    incr golden_skips;
    incr pass_count;
    Printf.printf "  SKIP %s (skipped: %s)\n" name reason
  in
  let pid = Unix.getpid () in
  let temp_path name =
    Filename.concat (Filename.get_temp_dir_name ()) (Printf.sprintf "tlang-golden-%d-%s" pid name)
  in
  let read_file_opt path =
    try
      let ic = open_in_bin path in
      Fun.protect ~finally:(fun () -> close_in_noerr ic)
        (fun () -> Some (really_input_string ic (in_channel_length ic)))
    with _ -> None
  in
  let with_temp_files paths f =
    Fun.protect ~finally:(fun () -> List.iter (fun p -> try Sys.remove p with _ -> ()) paths) f
  in
  (* Small JSON number reader: float following a "key": token. *)
  let json_number hay key =
    let pat = "\"" ^ key ^ "\":" in
    let h = String.length hay and n = String.length pat in
    let rec find i =
      if i + n > h then None
      else if String.sub hay i n = pat then begin
        let j = ref (i + n) in
        while !j < h && (hay.[!j] = ' ' || hay.[!j] = '\t') do incr j done;
        let k = ref !j in
        while !k < h &&
              (let c = hay.[!k] in
               (c >= '0' && c <= '9') || c = '.' || c = '-' || c = '+' || c = 'e' || c = 'E') do
          incr k
        done;
        if !k > !j then
          (try Some (float_of_string (String.sub hay !j (!k - !j))) with _ -> None)
        else None
      end else find (i + 1)
    in
    find 0
  in
  let write_temp name content =
    let path = temp_path name in
    (try
       let oc = open_out path in
       Fun.protect ~finally:(fun () -> close_out_noerr oc)
         (fun () -> output_string oc content);
       Some path
     with _ -> None)
  in
  (* R: full precision survives (digits = NA): tiny p-value unrounded,
     r_squared exact well past 4 significant digits. *)
  (match extract_fn "r_save_meta <- function(object, path) {" (fun l -> l = "}") with
   | None -> check_golden "R probe source found" false
   | Some _ when not (has_bin "Rscript") -> skip_golden "R probe golden" "no Rscript"
   | Some src ->
       let drv = src ^ "\n" ^
         "set.seed(42)\n" ^
         "tt <- t.test(rnorm(50, 0, 1), rnorm(50, 10, 1))\n" ^
         "r_save_meta(tt, Sys.getenv(\"T_GOLD_OUT\"))\n" ^
         "fit <- lm(mpg ~ wt + hp, data = mtcars)\n" ^
         "r_save_meta(fit, Sys.getenv(\"T_GOLD_OUT2\"))\n" ^
         "gfit <- mgcv::gam(mpg ~ s(wt) + hp, data = mtcars)\n" ^
         "r_save_meta(gfit, Sys.getenv(\"T_GOLD_OUT3\"))\n" ^
         "rfit <- MASS::rlm(mpg ~ wt, mtcars)\n" ^
         "r_save_meta(rfit, Sys.getenv(\"T_GOLD_OUT4\"))\n" ^
         "library(MASS)\n" ^
         "nbfit <- MASS::glm.nb(Days ~ Eth + Age, data = quine)\n" ^
         "r_save_meta(nbfit, Sys.getenv(\"T_GOLD_OUT5\"))\n" ^
         "sstl <- stl(AirPassengers, s.window = \"periodic\")\n" ^
         "r_save_meta(sstl, Sys.getenv(\"T_GOLD_OUT6\"))\n" ^
         "library(survival)\n" ^
         "cfit <- coxph(Surv(time, status) ~ age + sex, data = lung)\n" ^
         "r_save_meta(cfit, Sys.getenv(\"T_GOLD_OUT7\"))\n" ^
         "sfit <- survfit(Surv(time, status) ~ sex, data = lung)\n" ^
         "r_save_meta(sfit, Sys.getenv(\"T_GOLD_OUT8\"))\n" ^
         "library(rpart)\n" ^
         "rp <- rpart(Species ~ ., iris)\n" ^
         "r_save_meta(rp, Sys.getenv(\"T_GOLD_OUT9\"))\n" ^
         "dn <- density(mtcars$mpg)\n" ^
         "r_save_meta(dn, Sys.getenv(\"T_GOLD_OUT10\"))\n" ^
         "aa <- acf(AirPassengers, plot = FALSE)\n" ^
         "r_save_meta(aa, Sys.getenv(\"T_GOLD_OUT11\"))\n" ^
         "sp <- smooth.spline(mtcars$wt, mtcars$mpg)\n" ^
         "r_save_meta(sp, Sys.getenv(\"T_GOLD_OUT12\"))\n" ^
         "ec <- ecdf(mtcars$mpg)\n" ^
         "r_save_meta(ec, Sys.getenv(\"T_GOLD_OUT13\"))\n" ^
         "library(randomForest)\n" ^
         "rfr <- randomForest(Species ~ ., iris, ntree = 10)\n" ^
         "r_save_meta(rfr, Sys.getenv(\"T_GOLD_OUT14\"))\n" ^
         "km <- kmeans(mtcars, 3)\n" ^
         "r_save_meta(km, Sys.getenv(\"T_GOLD_OUT15\"))\n" ^
         "pc <- prcomp(mtcars)\n" ^
         "r_save_meta(pc, Sys.getenv(\"T_GOLD_OUT16\"))\n" ^
         "ar <- arima(AirPassengers, order = c(1, 1, 1))\n" ^
         "r_save_meta(ar, Sys.getenv(\"T_GOLD_OUT17\"))\n" ^
         "po <- MASS::polr(Sat ~ Infl + Type + Cont, data = housing, Hess = TRUE)\n" ^
         "r_save_meta(po, Sys.getenv(\"T_GOLD_OUT18\"))\n" ^
         "mn <- nnet::multinom(Species ~ ., iris, trace = FALSE)\n" ^
         "r_save_meta(mn, Sys.getenv(\"T_GOLD_OUT19\"))\n" ^
         "nn <- nnet::nnet(Species ~ ., iris, size = 2, trace = FALSE)\n" ^
         "r_save_meta(nn, Sys.getenv(\"T_GOLD_OUT20\"))\n" ^
         "library(xgboost)\n" ^
         "data(agaricus.train)\n" ^
         "dm <- xgb.DMatrix(agaricus.train$data, label = agaricus.train$label)\n" ^
         "bx <- xgb.train(list(objective = \"binary:logistic\", max_depth = 2), dm, nrounds = 5)\n" ^
         "r_save_meta(bx, Sys.getenv(\"T_GOLD_OUT21\"))\n" ^
         "library(lightgbm)\n" ^
         "ld <- lgb.Dataset(agaricus.train$data, label = agaricus.train$label)\n" ^
         "lb <- lgb.train(list(objective = \"binary\", num_leaves = 4), ld, 5)\n" ^
         "r_save_meta(lb, Sys.getenv(\"T_GOLD_OUT22\"))\n"
       in
       (match write_temp "r.R" drv with
        | None -> check_golden "R probe driver written" false
        | Some drv_path ->
            let out_path = temp_path "r.json" in
            let out2_path = temp_path "r2.json" in
            let out3_path = temp_path "r3.json" in
            let out4_path = temp_path "r4.json" in
            let out5_path = temp_path "r5.json" in
            let out6_path = temp_path "r6.json" in
            let out7_path = temp_path "r7.json" in
            let out8_path = temp_path "r8.json" in
            let out9_path = temp_path "r9.json" in
            let out10_path = temp_path "r10.json" in
            let out11_path = temp_path "r11.json" in
            let out12_path = temp_path "r12.json" in
            let out13_path = temp_path "r13.json" in
            let out14_path = temp_path "r14.json" in
            let out15_path = temp_path "r15.json" in
            let out16_path = temp_path "r16.json" in
            let out17_path = temp_path "r17.json" in
            let out18_path = temp_path "r18.json" in
            let out19_path = temp_path "r19.json" in
            let out20_path = temp_path "r20.json" in
            let out21_path = temp_path "r21.json" in
            let out22_path = temp_path "r22.json" in
            with_temp_files [drv_path; out_path; out2_path; out3_path; out4_path; out5_path; out6_path; out7_path; out8_path; out9_path; out10_path; out11_path; out12_path; out13_path; out14_path; out15_path; out16_path; out17_path; out18_path; out19_path; out20_path; out21_path; out22_path] (fun () ->
              let _ = shell_out (Printf.sprintf "T_GOLD_OUT=%s T_GOLD_OUT2=%s T_GOLD_OUT3=%s T_GOLD_OUT4=%s T_GOLD_OUT5=%s T_GOLD_OUT6=%s T_GOLD_OUT7=%s T_GOLD_OUT8=%s T_GOLD_OUT9=%s T_GOLD_OUT10=%s T_GOLD_OUT11=%s T_GOLD_OUT12=%s T_GOLD_OUT13=%s T_GOLD_OUT14=%s T_GOLD_OUT15=%s T_GOLD_OUT16=%s T_GOLD_OUT17=%s T_GOLD_OUT18=%s T_GOLD_OUT19=%s T_GOLD_OUT20=%s T_GOLD_OUT21=%s T_GOLD_OUT22=%s Rscript %s 2>/dev/null"
                (Filename.quote out_path) (Filename.quote out2_path) (Filename.quote out3_path) (Filename.quote out4_path) (Filename.quote out5_path) (Filename.quote out6_path) (Filename.quote out7_path) (Filename.quote out8_path) (Filename.quote out9_path) (Filename.quote out10_path) (Filename.quote out11_path) (Filename.quote out12_path) (Filename.quote out13_path) (Filename.quote out14_path) (Filename.quote out15_path) (Filename.quote out16_path) (Filename.quote out17_path) (Filename.quote out18_path) (Filename.quote out19_path) (Filename.quote out20_path) (Filename.quote out21_path) (Filename.quote out22_path) (Filename.quote drv_path)) in
              let json = match read_file_opt out_path with Some s -> s | None -> "" in
              let json2 = match read_file_opt out2_path with Some s -> s | None -> "" in
              let json3 = match read_file_opt out3_path with Some s -> s | None -> "" in
              let json4 = match read_file_opt out4_path with Some s -> s | None -> "" in
              let json5 = match read_file_opt out5_path with Some s -> s | None -> "" in
              let json6 = match read_file_opt out6_path with Some s -> s | None -> "" in
              let json7 = match read_file_opt out7_path with Some s -> s | None -> "" in
              let json8 = match read_file_opt out8_path with Some s -> s | None -> "" in
              let json9 = match read_file_opt out9_path with Some s -> s | None -> "" in
              let json10 = match read_file_opt out10_path with Some s -> s | None -> "" in
              let json11 = match read_file_opt out11_path with Some s -> s | None -> "" in
              let json12 = match read_file_opt out12_path with Some s -> s | None -> "" in
              let json13 = match read_file_opt out13_path with Some s -> s | None -> "" in
              let json14 = match read_file_opt out14_path with Some s -> s | None -> "" in
              let json15 = match read_file_opt out15_path with Some s -> s | None -> "" in
              let json16 = match read_file_opt out16_path with Some s -> s | None -> "" in
              let json17 = match read_file_opt out17_path with Some s -> s | None -> "" in
              let json18 = match read_file_opt out18_path with Some s -> s | None -> "" in
              let json19 = match read_file_opt out19_path with Some s -> s | None -> "" in
              let json20 = match read_file_opt out20_path with Some s -> s | None -> "" in
              let json21 = match read_file_opt out21_path with Some s -> s | None -> "" in
              let json22 = match read_file_opt out22_path with Some s -> s | None -> "" in
              check_golden "R probe keeps tiny p-values unrounded"
                (match json_number json "p_value" with Some f -> f < 1e-6 | None -> false);
              check_golden "R probe keeps full float precision"
                (match json_number json2 "r_squared" with
                 | Some f -> abs_float (f -. 0.826785451882791) < 1e-6
                 | None -> false);
              check_golden "R probe handles gam through the glm branch"
                (contains json3 "regression" && contains json3 "s(wt)");
              check_golden "R probe handles rlm through the lm branch"
                (contains json4 "regression" && contains json4 "n_obs");
              check_golden "R probe handles glm.nb through the glm branch"
                (contains json5 "regression" && contains json5 "n_features");
              check_golden "R probe handles stl decomposition"
                (contains json6 "time_series" && contains json6 "seasonal");
              check_golden "R probe handles coxph survival"
                (contains json7 "survival" && contains json7 "concordance");
              check_golden "R probe handles survfit curves"
                (contains json8 "survival" && contains json8 "n_groups");
              check_golden "R probe handles rpart trees"
                (contains json9 "n_nodes" && contains json9 "Petal");
              check_golden "R probe handles density estimates"
                (contains json10 "distribution" && contains json10 "bw");
              check_golden "R probe handles acf objects"
                (contains json11 "time_series" && contains json11 "correlation");
              check_golden "R probe handles smooth splines"
                (contains json12 "regression" && contains json12 "lambda");
              check_golden "R probe handles ecdf closures"
                (contains json13 "distribution" && contains json13 "n_obs");
              check_golden "R probe handles randomForest"
                (contains json14 "classification" && contains json14 "n_trees");
              check_golden "R probe handles kmeans"
                (contains json15 "clustering" && contains json15 "n_clusters");
              check_golden "R probe handles prcomp"
                (contains json16 "dim_reduction" && contains json16 "n_components");
              check_golden "R probe handles arima"
                (contains json17 "time_series" && contains json17 "order");
              check_golden "R probe handles polr"
                (contains json18 "classification" && contains json18 "n_features");
              check_golden "R probe handles multinom"
                (contains json19 "classification" && contains json19 "deviance");
              check_golden "R probe handles nnet"
                (contains json20 "model" && contains json20 "n_obs");
              check_golden "R probe handles xgboost"
                (contains json21 "model" && contains json21 "n_rounds");
              check_golden "R probe handles lightgbm"
                (contains json22 "model" && contains json22 "n_rounds"))));
  (* R merMod: needs lme4, skipped when absent. *)
  (match shell_out "Rscript -e \"cat(requireNamespace(\\\"lme4\\\", quietly = TRUE))\" 2>/dev/null" with
   | s when contains s "TRUE" ->
       (match extract_fn "r_save_meta <- function(object, path) {" (fun l -> l = "}") with
        | None -> check_golden "R probe source found" false
        | Some src ->
            let drv = src ^ "\n" ^
              "library(lme4)\n" ^
              "mm <- lmer(Reaction ~ Days + (Days | Subject), sleepstudy)\n" ^
              "r_save_meta(mm, Sys.getenv(\"T_GOLD_OUT\"))\n"
            in
            (match write_temp "merMod.R" drv with
             | None -> check_golden "R probe merMod driver written" false
             | Some drv_path ->
                 let out = temp_path "mermod.json" in
                 with_temp_files [drv_path; out] (fun () ->
                   let _ = shell_out (Printf.sprintf "T_GOLD_OUT=%s Rscript %s 2>/dev/null"
                     (Filename.quote out) (Filename.quote drv_path)) in
                   let json = match read_file_opt out with Some s -> s | None -> "" in
                   check_golden "R probe handles merMod"
                     (contains json "regression" && contains json "Subject"))))
   | _ -> skip_golden "R probe merMod" "no lme4");
  (* Python: array-API const excluded from features; NaN sanitized. *)
  (match extract_fn ~keep_end:false "def py_save_meta(obj, path):" (fun l -> l <> "" && l.[0] <> ' ' && l.[0] <> '\t') with
   | None -> check_golden "Python probe source found" false
   | Some _ when not (has_bin "python3") -> skip_golden "Python probe golden" "no python3"
   | Some src ->
       let pre = shell_out "python3 -c \"import pandas, statsmodels; print('IMPORT-OK')\" 2>/dev/null" in
       if not (contains pre "IMPORT-OK") then skip_golden "Python probe golden" "no pandas/statsmodels"
       else
         (match extract_fn ~keep_end:false "def _tlang_sanitize_json(v):" (fun l -> l <> "" && l.[0] <> ' ' && l.[0] <> '\t') with
          | None -> check_golden "Python sanitizer source found" false
          | Some san ->
          let drv = san ^ "\n" ^ src ^ "\n" ^
           "import numpy as np, pandas as pd\n" ^
           "import statsmodels.api as sm\n" ^
           "df = pd.DataFrame({\"y\": [2.0, 4.0, 5.0, 4.0], \"x\": [1.0, 2.0, 3.0, 4.0]})\n" ^
           "import os\n" ^
           "py_save_meta(sm.OLS(df[\"y\"], sm.add_constant(df[[\"x\"]])).fit(), os.environ[\"T_GOLD_OUT\"])\n" ^
           "from sklearn.ensemble import IsolationForest\n" ^
           "py_save_meta(IsolationForest().fit(np.array([[1.0],[2.0],[3.0]])), os.environ[\"T_GOLD_OUT3\"])\n" ^
           "from xgboost import XGBRanker\n" ^
           "_tlang_X = np.array([[1.0],[2.0],[3.0],[4.0]])\n" ^
           "py_save_meta(XGBRanker(n_estimators = 3).fit(_tlang_X, np.array([0, 0, 1, 1]), qid = np.array([0, 0, 0, 0])), os.environ[\"T_GOLD_OUT4\"])\n" ^
           "from scipy import stats as _tlang_stats\n" ^
           "py_save_meta(_tlang_stats.norm(0, 1), os.environ[\"T_GOLD_OUT5\"])\n" ^
           "import statsmodels.formula.api as _tlang_smf\n" ^
           "_tlang_mndf = pd.DataFrame({\"ym\": [0, 1, 1, 0, 1, 0], \"a\": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]})\n" ^
           "py_save_meta(_tlang_smf.mnlogit(\"ym ~ a\", _tlang_mndf).fit(disp=0), os.environ[\"T_GOLD_OUT6\"])\n" ^
           "from statsmodels.duration.hazard_regression import PHReg as _tlang_PHReg\n" ^
           "_tlang_phdf = pd.DataFrame({\"t\": [5.0, 6.0, 6.0, 2.5, 4.0, 4.0], \"e\": [1, 0, 0, 1, 1, 1], \"x\": [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]})\n" ^
           "py_save_meta(_tlang_PHReg(_tlang_phdf[\"t\"], _tlang_phdf[[\"x\"]], status=_tlang_phdf[\"e\"]).fit(), os.environ[\"T_GOLD_OUT7\"])\n" ^
           "from sklearn.linear_model import LogisticRegression as _tlang_LR\n" ^
           "from sklearn.calibration import CalibratedClassifierCV as _tlang_Cal\n" ^
           "_tlang_Xc = np.array([[1.0],[2.0],[3.0],[4.0],[5.0],[6.0],[7.0],[8.0]])\n" ^
           "py_save_meta(_tlang_Cal(_tlang_LR(), cv=2).fit(_tlang_Xc, np.array([0,0,0,0,1,1,1,1])), os.environ[\"T_GOLD_OUT8\"])\n" ^
           "from sklearn.multioutput import MultiOutputClassifier as _tlang_MOC\n" ^
           "py_save_meta(_tlang_MOC(_tlang_LR()).fit(_tlang_Xc, np.array([[0,1],[0,1],[0,0],[1,0],[1,0],[1,1],[0,1],[1,0]])), os.environ[\"T_GOLD_OUT9\"])\n" ^
           "import lightgbm as _tlang_lgb\n" ^
           "_tlang_ld = _tlang_lgb.Dataset(_tlang_Xc, label = np.array([0, 0, 1, 1, 2, 2, 0, 1]))\n" ^
           "_tlang_lb = _tlang_lgb.train({\"objective\": \"multiclass\", \"num_class\": 3, \"num_leaves\": 4, \"verbose\": -1}, _tlang_ld, num_boost_round = 4)\n" ^
           "py_save_meta(_tlang_lb, os.environ[\"T_GOLD_OUT10\"])\n" ^
           "from sklearn.pipeline import Pipeline as _tlang_Pipe\n" ^
           "from sklearn.preprocessing import StandardScaler as _tlang_SS\n" ^
           "from sklearn.linear_model import LogisticRegression as _tlang_LR2\n" ^
           "py_save_meta(_tlang_Pipe([(\"s\", _tlang_SS()), (\"c\", _tlang_LR2())]).fit(_tlang_Xc, np.array([0,0,0,0,1,1,1,1])), os.environ[\"T_GOLD_OUT11\"])\n" ^
           "san = _tlang_sanitize_json({\"kind\": \"model\", \"metrics\": {\"aic\": float(\"nan\"), \"bic\": 2.5}})\n" ^
           "import json as _tlang_json_check\n" ^
           "with open(os.environ[\"T_GOLD_OUT2\"], \"w\") as f: _tlang_json_check.dump(san, f)\n"
         in
         (match write_temp "py.py" drv with
          | None -> check_golden "Python probe driver written" false
          | Some drv_path ->
              let out_path = temp_path "py.json" in
              let out2_path = temp_path "py2.json" in
              let out3_path = temp_path "py3.json" in
              let out4_path = temp_path "py4.json" in
              let out5_path = temp_path "py5.json" in
              let out6_path = temp_path "py6.json" in
              let out7_path = temp_path "py7.json" in
              let out8_path = temp_path "py8.json" in
              let out9_path = temp_path "py9.json" in
              let out10_path = temp_path "py10.json" in
              let out11_path = temp_path "py11.json" in
              with_temp_files [drv_path; out_path; out2_path; out3_path; out4_path; out5_path; out6_path; out7_path; out8_path; out9_path; out10_path; out11_path] (fun () ->
                let _ = shell_out (Printf.sprintf "T_GOLD_OUT=%s T_GOLD_OUT2=%s T_GOLD_OUT3=%s T_GOLD_OUT4=%s T_GOLD_OUT5=%s T_GOLD_OUT6=%s T_GOLD_OUT7=%s T_GOLD_OUT8=%s T_GOLD_OUT9=%s T_GOLD_OUT10=%s T_GOLD_OUT11=%s python3 %s 2>/dev/null"
                  (Filename.quote out_path) (Filename.quote out2_path) (Filename.quote out3_path) (Filename.quote out4_path) (Filename.quote out5_path) (Filename.quote out6_path) (Filename.quote out7_path) (Filename.quote out8_path) (Filename.quote out9_path) (Filename.quote out10_path) (Filename.quote out11_path) (Filename.quote drv_path)) in
                let json = match read_file_opt out_path with Some s -> s | None -> "" in
                let json2 = match read_file_opt out2_path with Some s -> s | None -> "" in
                let json3 = match read_file_opt out3_path with Some s -> s | None -> "" in
                let json4 = match read_file_opt out4_path with Some s -> s | None -> "" in
                let json5 = match read_file_opt out5_path with Some s -> s | None -> "" in
                let json6 = match read_file_opt out6_path with Some s -> s | None -> "" in
                let json7 = match read_file_opt out7_path with Some s -> s | None -> "" in
                let json8 = match read_file_opt out8_path with Some s -> s | None -> "" in
                let json9 = match read_file_opt out9_path with Some s -> s | None -> "" in
                let json10 = match read_file_opt out10_path with Some s -> s | None -> "" in
                let json11 = match read_file_opt out11_path with Some s -> s | None -> "" in
                check_golden "Python probe excludes const from OLS features"
                  (contains json "\"x\"" && not (contains json "const"));
                check_golden "Python probe tags anomaly detectors"
                  (contains json3 "anomaly_detection");
                check_golden "Python probe tags rankers"
                  (contains json4 "ranking" && contains json4 "n_rounds");
                check_golden "Python probe handles frozen distributions"
                  (contains json5 "distribution" && contains json5 "norm");
                check_golden "Python probe handles multinomial logits"
                  (contains json6 "classification" && contains json6 "\"a\"");
                check_golden "Python probe handles Cox PH regression"
                  (contains json7 "survival" && contains json7 "loglik");
              check_golden "Python probe passes through calibrated classifiers"
                (contains json8 "classification" && contains json8 "n_features");
              check_golden "Python probe passes through multioutput wrappers"
                (contains json9 "classification" && contains json9 "n_features");
              check_golden "Python probe handles LightGBM multiclass rounds"
                (contains json10 "classification" && contains json10 "n_rounds");
              check_golden "Python probe passes through sklearn pipelines"
                (contains json11 "classification" && contains json11 "n_classes");
                check_golden "Python sanitizer drops NaN metrics, keeps the rest"
                  (contains json2 "bic" && not (contains json2 "aic"))))));
  (* Julia: end-to-end save_meta on a DataFrame plus the NaN sanitizer. *)
  (match extract_fn "function jl_sanitize_json_value(v)" (fun l -> l = "end") with
   | None -> check_golden "Julia sanitizer source found" false
   | Some _ when not (has_bin "julia") -> skip_golden "Julia sanitizer golden" "no julia"
   | Some san_src ->
       (* Real JSON is unavailable in bare dev shells (node envs ship
          it), so the driver stubs JSON.print and exercises the real
          detection paths plus file writing. *)
       let pre = shell_out "julia -e 'using DataFrames' 2>/dev/null && echo IMPORT-OK" in
       if not (contains pre "IMPORT-OK") then skip_golden "Julia golden" "no DataFrames"
       else
         (match extract_fn "function jl_save_meta(obj, path)" (fun l -> l = "end") with
          | None -> check_golden "Julia probe source found" false
          | Some probe ->
              let drv = san_src ^ "\n" ^ probe ^ "\n" ^
                "module JSON\n" ^
                "print(io::IO, d) = Base.print(io, d)\n" ^
                "end\n" ^
                "using DataFrames\n" ^
                "jl_save_meta(DataFrame(a = [1, 2, 3]), ENV[\"T_GOLD_OUT\"])\n" ^
                "struct TlangGoldMedoids\n" ^
                "    counts::Vector{Int}\n" ^
                "    medoids::Vector{Int}\n" ^
                "    totalcost::Float64\n" ^
                "end\n" ^
                "jl_save_meta(TlangGoldMedoids([2, 2], [1, 3], 4.0), ENV[\"T_GOLD_OUT3\"])\n" ^
                "struct TlangGoldTimeArray\n" ^
                "    timestamp::Vector{Int}\n" ^
                "    values::Matrix{Float64}\n" ^
                "end\n" ^
                "struct TlangGoldTree\n" ^
                "    feature::Int\n" ^
                "    threshold::Float64\n" ^
                "    left::Int\n" ^
                "    right::Int\n" ^
                "end\n" ^
                "struct TlangGoldTTest\n" ^
                "    pvalue::Float64\n" ^
                "    statistic::Float64\n" ^
                "end\n" ^
                "jl_save_meta(TlangGoldTimeArray([1,2,3], [1.0 2.0; 3.0 4.0; 5.0 6.0]), ENV[\"T_GOLD_OUT4\"])\n" ^
                "jl_save_meta(TlangGoldTree(2, 0.5, 1, 2), ENV[\"T_GOLD_OUT5\"])\n" ^
                "jl_save_meta(TlangGoldTTest(0.03, 2.1), ENV[\"T_GOLD_OUT6\"])\n" ^
                "d = jl_sanitize_json_value(Dict(\"kind\" => \"model\", \"metrics\" => Dict(\"aic\" => NaN, \"bic\" => 1.5)))\n" ^
                "open(ENV[\"T_GOLD_OUT2\"], \"w\") do f\n" ^
                "    print(f, d)\n" ^
                "end\n"
              in
              (match write_temp "jl.jl" drv with
               | None -> check_golden "Julia driver written" false
               | Some drv_path ->
                   let out_path = temp_path "jl.json" in
                   let out2_path = temp_path "jl2.json" in
                   let out3_path = temp_path "jl3.json" in
                   let out4_path = temp_path "jl4.json" in
                   let out5_path = temp_path "jl5.json" in
                   let out6_path = temp_path "jl6.json" in
                   with_temp_files [drv_path; out_path; out2_path; out3_path; out4_path; out5_path; out6_path] (fun () ->
                     let _ = shell_out (Printf.sprintf "T_GOLD_OUT=%s T_GOLD_OUT2=%s T_GOLD_OUT3=%s T_GOLD_OUT4=%s T_GOLD_OUT5=%s T_GOLD_OUT6=%s julia %s 2>/dev/null"
                       (Filename.quote out_path) (Filename.quote out2_path) (Filename.quote out3_path) (Filename.quote out4_path) (Filename.quote out5_path) (Filename.quote out6_path) (Filename.quote drv_path)) in
                     let json = match read_file_opt out_path with Some s -> s | None -> "" in
                     let txt = match read_file_opt out2_path with Some s -> s | None -> "" in
                     let json3 = match read_file_opt out3_path with Some s -> s | None -> "" in
                     let json4 = match read_file_opt out4_path with Some s -> s | None -> "" in
                     let json5 = match read_file_opt out5_path with Some s -> s | None -> "" in
                     let json6 = match read_file_opt out6_path with Some s -> s | None -> "" in
                     check_golden "Julia probe writes a real sidecar end to end"
                       (contains json "dataframe" && contains json "dimensions");
                     check_golden "Julia sanitizer drops NaN metrics, keeps the rest"
                       (contains txt "bic" && not (contains txt "aic"));
                     check_golden "Julia probe detects medoids clustering"
                       (contains json3 "clustering" && contains json3 "n_clusters");
                     check_golden "Julia probe handles time arrays"
                       (contains json4 "series" && contains json4 "n_obs");
                     check_golden "Julia probe handles single trees"
                       (contains json5 "model" && contains json5 "TlangGoldTree");
                     check_golden "Julia probe handles hypothesis tests"
                       (contains json6 "test" && contains json6 "p_value")))));
  (* Julia GLM: needs the GLM package, skipped when absent. *)
  (match shell_out "julia -e 'using GLM' 2>/dev/null && echo IMPORT-OK" with
   | pre when not (contains pre "IMPORT-OK") -> skip_golden "Julia GLM golden" "no GLM"
   | _ ->
       (match extract_fn "function jl_save_meta(obj, path)" (fun l -> l = "end") with
        | None -> check_golden "Julia probe source found" false
        | Some probe ->
            let san_src_opt = extract_fn "function jl_sanitize_json_value(v)" (fun l -> l = "end") in
            let drv = (match san_src_opt with Some s -> s ^ "\n" | None -> "") ^ probe ^ "\n" ^
              "module JSON\n" ^
              "print(io::IO, d) = Base.print(io, d)\n" ^
              "end\n" ^
              "using GLM, DataFrames\n" ^
              "df = DataFrame(x = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], y = [0, 0, 0, 1, 1, 1])\n" ^
              "m = glm(@formula(y ~ x), df, Binomial(), LogitLink())\n" ^
              "jl_save_meta(m, ENV[\"T_GOLD_OUT\"])\n"
            in
            (match write_temp "jlglm.jl" drv with
             | None -> check_golden "Julia GLM driver written" false
             | Some drv_path ->
                 let out = temp_path "jlglm.json" in
                 with_temp_files [drv_path; out] (fun () ->
                   let _ = shell_out (Printf.sprintf "T_GOLD_OUT=%s julia %s 2>/dev/null"
                     (Filename.quote out) (Filename.quote drv_path)) in
                   let json = match read_file_opt out with Some s -> s | None -> "" in
                   check_golden "Julia probe handles GLM fits"
                     (contains json "classification" && contains json "deviance")))));
  (* Skips are environmental (missing runtime), never code regressions:
     extraction breakage fails loudly above. They are reported loudly
     but do not fail, so cross-platform CI (e.g. macOS images without a
     runtime) stays green. Set TLANG_TEST_STRICT_GOLDEN=1 to fail on
     skips when the environment is known-complete. *)
  (if !golden_skips > 0 then begin
     Printf.printf "  (%d golden probe(s) skipped: runtimes unavailable)\n" !golden_skips;
     match Sys.getenv_opt "TLANG_TEST_STRICT_GOLDEN" with
     | Some _ ->
         incr fail_count;
         let msg = Printf.sprintf "  FAILURE golden probes skipped under TLANG_TEST_STRICT_GOLDEN\n" in
         failures := msg :: !failures;
         Printf.printf "%s" msg
     | None -> ()
   end);
  print_newline ()
