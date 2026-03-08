let run_tests pass_count fail_count _eval_string eval_string_env test =
  Printf.printf "Phase 3 — Basic Pipeline:\n";
  test "simple pipeline"
    "pipeline {\n  x = 1\n  y = 2\n  z = x + y\n}"
    "Pipeline(3 nodes: [x, y, z])";
  test "pipeline type"
    "type(pipeline {\n  a = 10\n})"
    {|"Pipeline"|};
  test "pipeline with expressions"
    "pipeline {\n  a = 2 * 3\n  b = a + 4\n}"
    "Pipeline(2 nodes: [a, b])";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Node Access:\n";
  let env_p3 = Packages.init_env () in
  let (_, env_p3) = eval_string_env "p = pipeline {\n  x = 10\n  y = 20\n  total = x + y\n}" env_p3 in
  let (v, _) = eval_string_env "p.x" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "10" then begin
    incr pass_count; Printf.printf "  ✓ pipeline node access via dot (x)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline node access via dot (x)\n    Expected: 10\n    Got: %s\n" result
  end;
  let (v, _) = eval_string_env "p.total" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "30" then begin
    incr pass_count; Printf.printf "  ✓ pipeline node access via dot (total)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline node access via dot (total)\n    Expected: 30\n    Got: %s\n" result
  end;
  let (v, _) = eval_string_env "p.nonexistent" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = {|Error(KeyError: "Node `nonexistent` not found in Pipeline.")|} then begin
    incr pass_count; Printf.printf "  ✓ missing pipeline node returns error\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ missing pipeline node returns error\n    Expected: Error(KeyError: ...)\n    Got: %s\n" result
  end;
  print_newline ();

  Printf.printf "Phase 3 — Deterministic Execution:\n";
  test "pipeline executes deterministically"
    "p1 = pipeline {\n  a = 5\n  b = a * 2\n  c = b + 1\n}; p2 = pipeline {\n  a = 5\n  b = a * 2\n  c = b + 1\n}; p1.c == p2.c"
    "true";
  print_newline ();

  Printf.printf "Phase 3 — Dependency Resolution:\n";
  test "out-of-order dependencies resolved"
    "p = pipeline {\n  result = x + y\n  x = 3\n  y = 7\n}; p.result"
    "10";
  test "chain dependencies"
    "p = pipeline {\n  a = 1\n  b = a + 1\n  c = b + 1\n  d = c + 1\n}; p.d"
    "4";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Introspection:\n";
  let (v, _) = eval_string_env "pipeline_nodes(p)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["x", "y", "total"]|} then begin
    incr pass_count; Printf.printf "  ✓ pipeline_nodes() lists all nodes\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_nodes() lists all nodes\n    Expected: [\"x\", \"y\", \"total\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env {|pipeline_node(p, "total")|} env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "30" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_node() gets specific node value\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_node() gets specific node value\n    Expected: 30\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "pipeline_deps(p)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`x`: [], `y`: [], `total`: ["x", "y"]}|} then begin
    incr pass_count; Printf.printf "  ✓ pipeline_deps() returns dependency graph\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_deps() returns dependency graph\n    Expected: {`x`: [], `y`: [], `total`: [\"x\", \"y\"]}\n    Got: %s\n" result
  end;

  test "pipeline_nodes on non-pipeline"
    "pipeline_nodes(42)"
    {|Error(TypeError: "Function `pipeline_nodes` expects a Pipeline.")|};
  test "pipeline_node missing key"
    {|p = pipeline { a = 1 }; pipeline_node(p, "b")|}
    {|Error(KeyError: "Node `b` not found in Pipeline.")|};
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Re-run (Caching):\n";
  let (v, _) = eval_string_env "pipeline_run(p)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if result = "Pipeline(3 nodes: [x, y, total])" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_run() re-runs and returns same result\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_run() re-runs and returns same result\n    Expected: Pipeline(3 nodes: [x, y, total])\n    Got: %s\n" result
  end;

  (* Re-run produces same node values *)
  let (rerun_result, _) = eval_string_env "p2 = pipeline_run(p); p2.total" env_p3 in
  let result = Ast.Utils.value_to_string rerun_result in
  if result = "30" then begin
    incr pass_count; Printf.printf "  ✓ re-run preserves cached values\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ re-run preserves cached values\n    Expected: 30\n    Got: %s\n" result
  end;

  test "pipeline_run on non-pipeline"
    "pipeline_run(42)"
    {|Error(TypeError: "Function `pipeline_run` expects a Pipeline.")|};
  print_newline ();

  Printf.printf "Pipeline Build and Artifact I/O:\n";
  test "build_pipeline returns output path"
    "p = pipeline {\n  a = 1\n  b = a + 2\n}\nout = build_pipeline(p)\nok = if (is_error(out)) (true) else (starts_with(out, \"/nix/store/\"))\nok"
    "true";
  test "read_node reads serialized artifact"
    "p = pipeline {\n  a = 1\n  b = a + 2\n}\nout = build_pipeline(p)\nok = if (is_error(out)) (error_code(read_node(\"b\")) == \"FileError\") else (read_node(\"b\") == 3)\nok"
    "true";
  test "read_node missing key"
    "p = pipeline {\n  a = 1\n}\nout = build_pipeline(p)\nok = if (is_error(out)) (error_code(read_node(\"missing\")) == \"FileError\") else (error_code(read_node(\"missing\")) == \"KeyError\")\nok"
    "true";
  print_newline ();

  Printf.printf "Serialization Builtins:\n";
  test "serialize and deserialize roundtrip"
    {|serialize([1, 2, 3], "test_roundtrip.tobj"); deserialize("test_roundtrip.tobj")|}
    "[1, 2, 3]";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline with Pipes:\n";
  test "pipeline with pipe operator"
    "double = \\(x) x * 2\np = pipeline {\n  a = 5\n  b = a |> double\n}; p.b"
    "10";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline with Functions:\n";
  test "pipeline with function calls"
    "p = pipeline {\n  data = [1, 2, 3]\n  total = sum(data)\n  count = length(data)\n}; p.total"
    "6";
  test "pipeline nodes available individually"
    "p = pipeline {\n  data = [1, 2, 3]\n  total = sum(data)\n  count = length(data)\n}; p.count"
    "3";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Error Handling:\n";
  test "pipeline cycle detection"
    "pipeline {\n  a = b\n  b = a\n}"
    {|Error(ValueError: "Pipeline has a dependency cycle involving node `a`.")|};
  test "pipeline with error in node"
    "pipeline {\n  a = 1 / 0\n  b = a + 1\n}"
    "Pipeline(2 nodes: [a, b])\nErrors:\n  - `a` failed: Division by zero.\n  - `b` failed: Upstream error: Division by zero.";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline with DataFrame:\n";
  (* Create CSV for pipeline DataFrame tests *)
  let csv_p3 = "test_phase3.csv" in
  let oc5 = open_out csv_p3 in
  output_string oc5 "name,value\nAlice,10\nBob,20\nCharlie,30\n";
  close_out oc5;

  let (_, env_p3_df) = eval_string_env (Printf.sprintf
    {|p = pipeline {
  data = read_csv("%s")
  rows = data |> nrow
  cols = data |> ncol
  names = data |> colnames
}|} csv_p3) (Packages.init_env ()) in
  let (v, _) = eval_string_env "p.rows" env_p3_df in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ pipeline with DataFrame nrow\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline with DataFrame nrow\n    Expected: 3\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "p.cols" env_p3_df in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ pipeline with DataFrame ncol\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline with DataFrame ncol\n    Expected: 2\n    Got: %s\n" result
  end;
  (try Sys.remove csv_p3 with _ -> ());
  print_newline ();

  Printf.printf "Phase 3 — Explicit Node Configuration (cross-runtime):\n";
  let explicit_node_code = {|
p_cross = pipeline {
  a = 10
  b = node(command = <{ a * 2 }>, runtime = R, serializer = write_rds, deserializer = read_rds, functions = "my_utils.R")
  c = node(command = <{ b + 1 }>, runtime = Python, serializer = write_pkl, deserializer = read_pkl, functions = ["my_utils.py", "my_serializer.py"], include = "data.csv")
}
  |} in
  let (_, env_cross) = eval_string_env explicit_node_code (Packages.init_env ()) in
  let (v_cross, _) = eval_string_env "pipeline_nodes(p_cross)" env_cross in
  let cross_nodes = Ast.Utils.value_to_string v_cross in
  if cross_nodes = "[\"a\", \"b\", \"c\"]" then begin
    incr pass_count; Printf.printf "  ✓ pipeline implicit and explicit nodes parsed\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline explicit nodes failed\n    Got: %s\n" cross_nodes
  end;

  (* Verify that explain indicates the different nodes *)
  let (v_explain, _) = eval_string_env "explain(p_cross).node_count" env_cross in
  if Ast.Utils.value_to_string v_explain = "3" then begin
    incr pass_count; Printf.printf "  ✓ cross-runtime node count correct\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ cross-runtime node count failed\n"
  end;

  print_newline ();

  Printf.printf "Phase 3 — Script-based Nodes:\n";
  (* Test: node() with both command and script returns an error *)
  test "node() cannot use both command and script"
    {|node(command = <{ 1 + 1 }>, script = "test.R", runtime = R)|}
    {|Error(TypeError: "node() cannot use both 'command' and 'script' arguments — choose one.")|};

  (* Test: node() with script argument creates a VNode with the script path *)
  let (v_script_node, _) = eval_string_env
    {|node(script = "train_model.R", runtime = R)|}
    (Packages.init_env ()) in
  (match v_script_node with
    | Ast.VNode un ->
        if un.un_script = Some "train_model.R" && un.un_runtime = "R" then begin
          incr pass_count; Printf.printf "  ✓ node() with script stores path and runtime\n"
        end else begin
          incr fail_count; Printf.printf "  ✗ node() with script stores path and runtime\n    script=%s runtime=%s\n"
            (match un.un_script with Some s -> s | None -> "None") un.un_runtime
        end
    | other ->
        incr fail_count; Printf.printf "  ✗ node() with script returned unexpected value: %s\n"
          (Ast.Utils.value_to_string other));

  let (v_py_node, _) = eval_string_env
    {|py(command = <{ x + 1 }>, env_vars = [API_KEY: "secret", RETRIES: 3])|}
    (Packages.init_env ()) in
  let same_env_vars left right =
    let sort_vars vars = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) vars in
    sort_vars left = sort_vars right
  in
  (match v_py_node with
   | Ast.VNode un
     when un.un_runtime = "Python"
          && same_env_vars un.un_env_vars [("API_KEY", Ast.VString "secret"); ("RETRIES", Ast.VInt 3)] ->
       incr pass_count; Printf.printf "  ✓ py() stores env_vars on the node\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ py() env_vars parsing failed: %s\n"
         (Ast.Utils.value_to_string other));

  test "node env_vars must be a dict"
    {|node(command = 1, env_vars = 1)|}
    {|Error(TypeError: "Function `node` expects `env_vars` to be a Dict.")|};

  let (v_py_pipeline, _) = eval_string_env
    {|pipeline {
  data = 1
  step = py(command = <{ data + 1 }>, env_vars = [MODE: "fast"])
}|}
    (Packages.init_env ()) in
  (match v_py_pipeline with
   | Ast.VPipeline p ->
       let runtime_ok = List.assoc_opt "step" p.p_runtimes = Some "Python" in
       let env_ok =
         match List.assoc_opt "step" p.p_env_vars with
         | Some vars -> same_env_vars vars [("MODE", Ast.VString "fast")]
         | None -> false
       in
       if runtime_ok && env_ok then begin
         incr pass_count; Printf.printf "  ✓ py() nodes are desugared with env_vars in pipelines\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ py() pipeline desugaring failed\n"
       end
   | other ->
       incr fail_count; Printf.printf "  ✗ py() pipeline should return VPipeline, got: %s\n"
         (Ast.Utils.value_to_string other));

  let (v_env_pipeline, _) = eval_string_env
    {|pipeline {
  model = rn(command = <{ 1 + 1 }>, env_vars = [MODEL_MODE: "train", RETRIES: 2])
}|}
    (Packages.init_env ()) in
  (match v_env_pipeline with
   | Ast.VPipeline p ->
       let rerun_has_envs =
         match Eval.rerun_pipeline (ref (Packages.init_env ())) p with
         | Ast.VPipeline rerun ->
             (match List.assoc_opt "model" rerun.p_env_vars with
              | Some vars -> same_env_vars vars [("MODEL_MODE", Ast.VString "train"); ("RETRIES", Ast.VInt 2)]
              | _ -> false)
         | _ -> false
       in
       let nix = Nix_emit_pipeline.emit_pipeline p in
       let contains s sub =
         try ignore (Str.search_forward (Str.regexp_string sub) s 0); true
         with Not_found -> false
       in
       let has_model_mode = contains nix {|"MODEL_MODE" = "train";|} in
       let has_retries = contains nix {|"RETRIES" = "2";|} in
       if rerun_has_envs && has_model_mode && has_retries then begin
         incr pass_count; Printf.printf "  ✓ pipeline preserves and emits node env_vars\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ pipeline env_vars preservation/emission failed\n"
       end
   | other ->
       incr fail_count; Printf.printf "  ✗ pipeline with env_vars should return VPipeline, got: %s\n"
         (Ast.Utils.value_to_string other));

  (* Test: runtime auto-detected from .R extension *)
  let (v_r_auto, _) = eval_string_env
    {|node(script = "my_script.R")|}
    (Packages.init_env ()) in
  (match v_r_auto with
   | Ast.VNode un when un.un_runtime = "R" ->
       incr pass_count; Printf.printf "  ✓ runtime auto-detected as R for .R script\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ runtime auto-detection for .R failed: %s\n"
         (Ast.Utils.value_to_string other));

  (* Test: runtime auto-detected from .py extension *)
  let (v_py_auto, _) = eval_string_env
    {|node(script = "my_script.py")|}
    (Packages.init_env ()) in
  (match v_py_auto with
   | Ast.VNode un when un.un_runtime = "Python" ->
       incr pass_count; Printf.printf "  ✓ runtime auto-detected as Python for .py script\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ runtime auto-detection for .py failed: %s\n"
         (Ast.Utils.value_to_string other));

  (* Test: script field accessible via dot access *)
  let (v_dot_script, _) = eval_string_env
    {|n = node(script = "fit.R", runtime = R); n.script|}
    (Packages.init_env ()) in
  let dot_script_s = Ast.Utils.value_to_string v_dot_script in
  if dot_script_s = {|"fit.R"|} then begin
    incr pass_count; Printf.printf "  ✓ node.script dot access returns script path\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ node.script dot access\n    Expected: \"fit.R\"\n    Got: %s\n" dot_script_s
  end;

  (* Test: script=null node returns null for .script *)
  let (v_no_script, _) = eval_string_env
    {|n = node(command = <{ 42 }>, runtime = R); n.script|}
    (Packages.init_env ()) in
  if Ast.Utils.value_to_string v_no_script = "null" then begin
    incr pass_count; Printf.printf "  ✓ node without script returns null for .script\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ node without script .script field\n    Expected: null\n    Got: %s\n"
      (Ast.Utils.value_to_string v_no_script)
  end;

  (* Test: pipeline with script-based node creates correct node structure *)
  let (v_pipeline_script, _) = eval_string_env
    {|p = pipeline {
  data = [1, 2, 3]
  result = node(script = "compute.R", runtime = R)
}; pipeline_nodes(p)|}
    (Packages.init_env ()) in
  let pipeline_nodes_s = Ast.Utils.value_to_string v_pipeline_script in
  if pipeline_nodes_s = {|["data", "result"]|} then begin
    incr pass_count; Printf.printf "  ✓ pipeline with script node has correct node list\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline with script node\n    Expected: [\"data\", \"result\"]\n    Got: %s\n" pipeline_nodes_s
  end;

  print_newline ()
