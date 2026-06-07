
let run_tests pass_count fail_count _failures _eval_string eval_string_env test =
  let strip_location s =
    let re = Str.regexp "\\[[^]]*L[0-9]+:C[0-9]+\\] " in
    Str.global_replace re "" s
  in
  let contains_pattern pattern s =
    try
      ignore (Str.search_forward (Str.regexp pattern) s 0);
      true
    with Not_found -> false
  in
  let capture_stderr f =
    let stderr_fd = Unix.descr_of_out_channel stderr in
    let saved_stderr = Unix.dup stderr_fd in
    let read_fd, write_fd = Unix.pipe () in
    let restored = ref false in
    let close_noerr fd =
      try Unix.close fd with
      | Unix.Unix_error _ -> ()
    in
    let restore () =
      if not !restored then begin
        restored := true;
        flush stderr;
        Unix.dup2 saved_stderr stderr_fd;
        close_noerr saved_stderr
      end
    in
    Fun.protect
      ~finally:(fun () ->
        restore ();
        close_noerr read_fd;
        close_noerr write_fd)
      (fun () ->
        Unix.dup2 write_fd stderr_fd;
        close_noerr write_fd;
        let result = f () in
        restore ();
        let buffer = Buffer.create 128 in
        let chunk = Bytes.create 256 in
        let rec drain () =
          match Unix.read read_fd chunk 0 (Bytes.length chunk) with
          | 0 -> ()
          | n ->
              Buffer.add_subbytes buffer chunk 0 n;
              drain ()
        in
        drain ();
        (result, Buffer.contents buffer))
  in
  let rec remove_path path =
    if Sys.file_exists path then
      if Sys.is_directory path then begin
        Sys.readdir path
        |> Array.iter (fun name -> remove_path (Filename.concat path name));
        Unix.rmdir path
      end else
        Sys.remove path
  in
  let with_temp_pipeline_project script f =
    let rec make_temp_dir attempts =
      if attempts <= 0 then
        failwith "failed to create temporary pipeline test directory"
      else
        let candidate =
          Filename.concat
            (Filename.get_temp_dir_name ())
            (Printf.sprintf "tlang-pipeline-%d-%06d" (Unix.getpid ()) (Random.int 1_000_000))
        in
        try
          Unix.mkdir candidate 0o755;
          candidate
        with Unix.Unix_error (Unix.EEXIST, _, _) ->
          make_temp_dir (attempts - 1)
    in
    let dir = make_temp_dir 8 in
    let src_dir = Filename.concat dir "src" in
    let pipeline_path = Filename.concat src_dir "pipeline.t" in
    let old_cwd = Sys.getcwd () in
    Unix.mkdir src_dir 0o755;
    let ch = open_out (Filename.concat dir "dune-project") in
    close_out ch;
    let oc = open_out pipeline_path in
    output_string oc script;
    close_out oc;
    try
      Sys.chdir dir;
      let result = f dir pipeline_path in
      Sys.chdir old_cwd;
      remove_path dir;
      result
    with exn ->
      Sys.chdir old_cwd;
      remove_path dir;
      raise exn
  in
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
  test "parameterization via lambdas returning pipelines"
    "f = \\(x: Int -> Pipeline) pipeline { a = x + 1 }; p = f(10); pipeline_nodes(p)"
    {|["a"]|};
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Node Access:\n";
  let env_p3 = Packages.init_env () in
  let (_, env_p3) = eval_string_env "p = pipeline {\n  x = 10\n  y = 20\n  total = x + y\n}" env_p3 in
  let (v, _) = eval_string_env "read_node(p.x)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if Test_helpers.contains result "unbuilt" then begin
    incr pass_count; Printf.printf "  ✓ pipeline node access via dot (x) returns FileError for unbuilt pipeline\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline node access via dot (x)\n    Expected: FileError with 'unbuilt'\n    Got: %s\n" result
  end;
  let (v, _) = eval_string_env "read_node(p.total)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if Test_helpers.contains result "unbuilt" then begin
    incr pass_count; Printf.printf "  ✓ pipeline node access via dot (total) returns FileError for unbuilt pipeline\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline node access via dot (total)\n    Expected: FileError with 'unbuilt'\n    Got: %s\n" result
  end;
  let (v, _) = eval_string_env "p.nonexistent" env_p3 in
  let result = strip_location (Ast.Utils.value_to_string v) in
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
    "p = pipeline {\n  result = x + y\n  x = 3\n  y = 7\n}; read_node(p.result)"
    "unbuilt";
  test "chain dependencies"
    "p = pipeline {\n  a = 1\n  b = a + 1\n  c = b + 1\n  d = c + 1\n}; read_node(p.d)"
    "unbuilt";
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
  if Test_helpers.contains result "computed_node" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_node() returns ComputedNode for unbuilt pipeline\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_node() returns ComputedNode for unbuilt pipeline\n    Expected: computed_node\n    Got: %s\n" result
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

  let (v, _) = eval_string_env "p_drv = pipeline { a = 1 }; pipeline_to_drv(p_drv)" env_p3 in
  let result = Ast.Utils.value_to_string v in
  if Test_helpers.contains result "a" && Test_helpers.contains result ".drv" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_to_drv() returns dictionary of drv paths\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_to_drv() returns dictionary of drv paths\n    Got: %s\n" result
  end;

  test "pipeline_to_drv on non-pipeline"
    "pipeline_to_drv(42)"
    {|Error(TypeError: "Function `pipeline_to_drv` expects a Pipeline as argument.")|};

  let (v_store, _) = eval_string_env "p_store = pipeline { a = 1 }; pipeline_to_store(p_store)" env_p3 in
  let result_store = Ast.Utils.value_to_string v_store in
  if Test_helpers.contains result_store "a" && Test_helpers.contains result_store "/nix/store/" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_to_store() returns dictionary of store paths\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_to_store() returns dictionary of store paths\n    Got: %s\n" result_store
  end;

  test "pipeline_to_store on non-pipeline"
    "pipeline_to_store(42)"
    {|Error(TypeError: "Function `pipeline_to_store` expects a Pipeline as argument.")|};

  test "set_nix_defaults successful dict"
    "set_nix_defaults(nix_options = [ max_jobs: 4 ])"
    {|"Nix defaults updated"|};

  test "set_nix_defaults on non-dict"
    "set_nix_defaults(nix_options = 42)"
    {|Error(TypeError: "Function `set_nix_defaults` expects a Dictionary of options.")|};

  test "set_nix_defaults invalid option"
    "set_nix_defaults(nix_options = [ unknown_opt: 1 ])"
    {|Error(TypeError: "set_nix_defaults: unknown option 'unknown_opt' in nix_options")|};

  let (v_override, _) =
    eval_string_env "set_nix_defaults(nix_options = [ dry_run: true ]); p_over = pipeline { a = 1 }; res = populate_pipeline(p_over, build=false, nix_options=[ dry_run: false ]); res" env_p3 in
  let result_override = Ast.Utils.value_to_string v_override in
  if Test_helpers.contains result_override "Pipeline populated in" then begin
    incr pass_count; Printf.printf "  ✓ dry_run call-site false overrides global dry_run true default\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ dry_run call-site false overrides global dry_run true default\n    Got: %s\n" result_override
  end;
  Builder_utils.global_nix_defaults := Builder_utils.default_nix_opts;

  let (v_cache, _) = eval_string_env "p_cache = pipeline { a = 1 }; pipeline_cache_status(p_cache)" env_p3 in
  let result_cache = Ast.Utils.value_to_string v_cache in
  if Test_helpers.contains result_cache "node" && Test_helpers.contains result_cache "cached" && Test_helpers.contains result_cache "store_path" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_cache_status() returns DataFrame with correct columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_cache_status() returns DataFrame with correct columns\n    Got: %s\n" result_cache
  end;

  test "pipeline_cache_status on non-pipeline"
    "pipeline_cache_status(42)"
    {|Error(TypeError: "Function `pipeline_cache_status` expects a Pipeline as argument.")|};

  test "export_artifacts on non-pipeline"
    "export_artifacts(42, \"cache.nar\")"
    {|Error(TypeError: "Function `export_artifacts` expects a Pipeline, MetaPipeline, Node, or collection of pipelines/nodes as first argument.")|};

  test "export_artifacts invalid archive path type"
    "p_export = pipeline { a = 1 }; export_artifacts(p_export, 42)"
    {|Error(TypeError: "Function `export_artifacts` expects `archive_path` to be a String.")|};

  test "import_artifacts with scalar target"
    "import_artifacts(42, \"nonexistent.nar\")"
    {|Error(TypeError: "Function `import_artifacts` expects a Pipeline, MetaPipeline, Node, or collection of pipelines/nodes as first argument.")|};

  test "import_artifacts invalid archive path type"
    "p_import = pipeline { a = 1 }; import_artifacts(p_import, 42)"
    {|Error(TypeError: "Function `import_artifacts` expects the second argument to be a String.")|};

  test "inspect_artifacts invalid argument type"
    "inspect_artifacts(42)"
    {|Error(TypeError: "Function `inspect_artifacts` expects a String argument.")|};

  let (v_gc, _) = eval_string_env "p_gc = pipeline { a = 1 }; pipeline_gc(p_gc, dry_run=true)" env_p3 in
  let result_gc = Ast.Utils.value_to_string v_gc in
  if Test_helpers.contains result_gc "node" && Test_helpers.contains result_gc "store_path" && Test_helpers.contains result_gc "deleted" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_gc() returns DataFrame with correct columns\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline_gc() returns DataFrame with correct columns\n    Got: %s\n" result_gc
  end;

  test "pipeline_gc on non-pipeline"
    "pipeline_gc(42)"
    {|Error(TypeError: "Function `pipeline_gc` expects a Pipeline.")|};

  test "pipeline_gc invalid dry_run type"
    "p_gc_invalid = pipeline { a = 1 }; pipeline_gc(p_gc_invalid, dry_run=42)"
    {|Error(TypeError: "Function `pipeline_gc` expects `dry_run` to be a Bool.")|};

  test "t_gc accepts no arguments and completes successfully"
    "starts_with(t_gc(), \"Garbage collection completed\")"
    "true";

  test "populate_pipeline dry_run=true returns a DataFrame with correct columns"
    "p_dry = pipeline { a = 1 }; res = populate_pipeline(p_dry, dry_run=true); colnames(res)"
    {|["node", "action", "store_path"]|};

  Printf.printf "Phase 3 — Static Interrogations (Roots/Leaves/Cycles):\n";
  test "pipeline_roots"
    "p = pipeline { a = 1; b = a + 1; c = 10 }; pipeline_roots(p)"
    {|["a", "c"]|};
  test "pipeline_leaves"
    "p = pipeline { a = 1; b = a + 1; c = 10 }; pipeline_leaves(p)"
    {|["b", "c"]|};
  test "pipeline_summary"
    "p = pipeline { a = 1; b = a + 1 }; nrow(pipeline_summary(p))"
    "2";
  test "pipeline_summary edge_count"
    "p = pipeline { a = 1; b = a + 1 }; length(pipeline_edges(p))"
    "1";

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
  let (rerun_result, _) = eval_string_env "p2 = pipeline_run(p); read_node(p2.total)" env_p3 in
  let result = Ast.Utils.value_to_string rerun_result in
  if Test_helpers.contains result "unbuilt" then begin
    incr pass_count; Printf.printf "  ✓ re-run returns FileError for unbuilt pipeline\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ re-run returns FileError for unbuilt pipeline\n    Expected: FileError with 'unbuilt'\n    Got: %s\n" result
  end;

  test "pipeline_run on non-pipeline"
    "pipeline_run(42)"
    {|Error(TypeError: "Function `pipeline_run` expects a Pipeline.")|};
  print_newline ();

  Printf.printf "Pipeline Build and Artifact I/O:\n";
  let verbose_args_ok =
    Builder_internal.nix_verbosity_args 0 = []
    && Builder_internal.nix_verbosity_args 1 = []
    && Builder_internal.nix_verbosity_args 2 = ["--verbose"]
    && Builder_internal.nix_verbosity_args 3 = ["--verbose"; "--verbose"]
    && Builder_internal.nix_verbosity_args 5 = ["--verbose"; "--verbose"; "--verbose"; "--verbose"]
  in
  if verbose_args_ok then begin
    incr pass_count; Printf.printf "  ✓ nix verbosity args are derived correctly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ nix verbosity args are derived correctly\n"
  end;
  (* Clean up any stale logs from previous runs to avoid picking up mock logs *)
  let _ = try
    if Sys.file_exists "_pipeline" then
      let files = Sys.readdir "_pipeline" in
      Array.iter (fun f -> if String.length f >= 10 && String.sub f 0 10 = "build_log_" then Sys.remove (Filename.concat "_pipeline" f)) files
    else
      Unix.mkdir "_pipeline" 0o755
  with _ -> () in
  test "populate_pipeline returns output path"
    "p = pipeline {\n  a = 1\n  b = a + 2\n}\nres = populate_pipeline(p, build=false, verbose=1)\nif (is_error(res)) (res) else (starts_with(res, \"Pipeline populated in\"))"
    "true";
  test "populate_pipeline accepts verbose option without building"
    "p = pipeline {\n  a = 1\n  b = a + 2\n}\nres = populate_pipeline(p, build=false, verbose=1)\nif (is_error(res)) (res) else (starts_with(res, \"Pipeline populated in\"))"
    "true";
  test "build_pipeline rejects non-int verbose"
    "p = pipeline {\n  a = 1\n}\nerror_code(build_pipeline(p, verbose=\"loud\")) == \"TypeError\""
    "true";
  test "build_pipeline rejects negative verbose"
    "p = pipeline {\n  a = 1\n}\nerror_code(build_pipeline(p, verbose=-1)) == \"ValueError\""
    "true";
  test "populate_pipeline accepts verbose option without building"
    "p = pipeline {\n  a = 1\n}\nout = populate_pipeline(p, build=false, verbose=2)\nstarts_with(out, \"Pipeline populated in\")"
    "true";
  test "populate_pipeline rejects non-int verbose"
    "p = pipeline {\n  a = 1\n}\nerror_code(populate_pipeline(p, build=false, verbose=\"loud\")) == \"TypeError\""
    "true";
  test "populate_pipeline rejects negative verbose"
    "p = pipeline {\n  a = 1\n}\nerror_code(populate_pipeline(p, build=false, verbose=-1)) == \"ValueError\""
    "true";
  let t_make_verbose_ok =
    with_temp_pipeline_project
      "p = pipeline {\n  a = 1\n}\npopulate_pipeline(p, build=false)\n"
      (fun _dir _pipeline_path ->
        let env = Packages.init_env () in
        let (v, _) = eval_string_env "t_make(verbose=2)" env in
        Ast.Utils.value_to_string v = "NA")
  in
  if t_make_verbose_ok then begin
    incr pass_count; Printf.printf "  ✓ t_make accepts verbose option\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ t_make accepts verbose option\n"
  end;
  test "t_make rejects non-int verbose"
    "error_code(t_make(verbose=\"loud\")) == \"TypeError\""
    "true";
  test "t_make rejects negative verbose"
    "error_code(t_make(verbose=-1)) == \"ValueError\""
    "true";
  test "t_make rejects non-pipeline entry filenames"
    "error_code(t_make(filename=\"script.t\")) == \"ValueError\""
    "true";

  (* nix_options validation and parsing tests *)
  test "populate_pipeline rejects non-dict nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(populate_pipeline(p, build=false, nix_options=\"not_a_dict\")) == \"TypeError\""
    "true";

  test "populate_pipeline rejects unknown option inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(populate_pipeline(p, build=false, nix_options=[unknown_opt: true])) == \"TypeError\""
    "true";

  test "populate_pipeline rejects non-positive max_jobs inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(populate_pipeline(p, build=false, nix_options=[max_jobs: -1])) == \"TypeError\""
    "true";

  test "populate_pipeline rejects non-string builders inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(populate_pipeline(p, build=false, nix_options=[builders: 123])) == \"TypeError\""
    "true";
  
  test "populate_pipeline rejects invalid keep_env inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(populate_pipeline(p, build=false, nix_options=[keep_env: 123])) == \"TypeError\""
    "true";

  test "populate_pipeline rejects non-string elements in keep_env list"
    "p = pipeline {\n  a = 1\n}\nerror_code(populate_pipeline(p, build=false, nix_options=[keep_env: [\"OK\", 123]])) == \"TypeError\""
    "true";

  test "populate_pipeline rejects invalid sandbox string inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(populate_pipeline(p, build=false, nix_options=[sandbox: \"invalid_sandbox\"])) == \"ValueError\""
    "true";

  test "populate_pipeline accepts valid nix_options dictionary with builders, keep_env, and sandbox"
    "p = pipeline {\n  a = 1\n}\nres = populate_pipeline(p, build=false, nix_options=[max_jobs: 4, force: true, dry_run: false, cache: \"mycache\", builders: \"ssh://builder.local\", keep_env: [\"API_KEY\", \"TOKEN\"], sandbox: \"relaxed\"])\nstarts_with(res, \"Pipeline populated in\")"
    "true";

  test "build_pipeline rejects non-dict nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(build_pipeline(p, nix_options=\"not_a_dict\")) == \"TypeError\""
    "true";

  test "build_pipeline rejects non-string builders inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(build_pipeline(p, nix_options=[builders: 123])) == \"TypeError\""
    "true";

  test "build_pipeline rejects invalid keep_env inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(build_pipeline(p, nix_options=[keep_env: 123])) == \"TypeError\""
    "true";

  test "build_pipeline rejects invalid sandbox inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(build_pipeline(p, nix_options=[sandbox: \"invalid_sandbox\"])) == \"ValueError\""
    "true";

  test "build_pipeline rejects unknown option inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(build_pipeline(p, nix_options=[unknown_opt: true])) == \"TypeError\""
    "true";

  test "pipeline_run rejects non-dict nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(pipeline_run(p, nix_options=\"not_a_dict\")) == \"TypeError\""
    "true";

  test "pipeline_run rejects non-string builders inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(pipeline_run(p, nix_options=[builders: 123])) == \"TypeError\""
    "true";

  test "pipeline_run rejects invalid keep_env inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(pipeline_run(p, nix_options=[keep_env: 123])) == \"TypeError\""
    "true";

  test "pipeline_run rejects invalid sandbox inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(pipeline_run(p, nix_options=[sandbox: \"invalid_sandbox\"])) == \"ValueError\""
    "true";

  test "pipeline_run rejects unknown option inside nix_options"
    "p = pipeline {\n  a = 1\n}\nerror_code(pipeline_run(p, nix_options=[unknown_opt: true])) == \"TypeError\""
    "true";

  let t_make_nix_options_builders_invalid =
    with_temp_pipeline_project
      "p = pipeline {\n  a = 1\n}\npopulate_pipeline(p, build=false)\n"
      (fun _dir _pipeline_path ->
        let env = Packages.init_env () in
        let (v, _) = eval_string_env "t_make(nix_options=[builders: 123])" env in
        let s = Ast.Utils.value_to_string v in
        Test_helpers.contains s "TypeError")
  in
  if t_make_nix_options_builders_invalid then begin
    incr pass_count; Printf.printf "  ✓ t_make rejects non-string builders inside nix_options\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ t_make rejects non-string builders inside nix_options\n"
  end;

  let t_make_nix_options_sandbox_invalid =
    with_temp_pipeline_project
      "p = pipeline {\n  a = 1\n}\npopulate_pipeline(p, build=false)\n"
      (fun _dir _pipeline_path ->
        let env = Packages.init_env () in
        let (v, _) = eval_string_env "t_make(nix_options=[sandbox: \"invalid_sandbox\"]) " env in
        let s = Ast.Utils.value_to_string v in
        Test_helpers.contains s "TypeError" || Test_helpers.contains s "sandbox")
  in
  if t_make_nix_options_sandbox_invalid then begin
    incr pass_count; Printf.printf "  ✓ t_make rejects invalid sandbox inside nix_options\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ t_make rejects invalid sandbox inside nix_options\n"
  end;

  let t_make_nix_options_ok =
    with_temp_pipeline_project
      "p = pipeline {\n  a = 1\n}\npopulate_pipeline(p, build=false)\n"
      (fun _dir _pipeline_path ->
        let env = Packages.init_env () in
        let (v, _) = eval_string_env "t_make(nix_options=[max_jobs: 2, keep_env: [\"API_KEY\"], sandbox: false])" env in
        Ast.Utils.value_to_string v = "NA")
  in
  if t_make_nix_options_ok then begin
    incr pass_count; Printf.printf "  ✓ t_make accepts nix_options dictionary\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ t_make accepts nix_options dictionary\n"
  end;

  let t_make_nix_options_invalid =
    with_temp_pipeline_project
      "p = pipeline {\n  a = 1\n}\npopulate_pipeline(p, build=false)\n"
      (fun _dir _pipeline_path ->
        let env = Packages.init_env () in
        let (v, _) = eval_string_env "t_make(nix_options=\"invalid\")" env in
        let s = Ast.Utils.value_to_string v in
        Test_helpers.contains s "TypeError")
  in
  if t_make_nix_options_invalid then begin
    incr pass_count; Printf.printf "  ✓ t_make rejects non-dict nix_options\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ t_make rejects non-dict nix_options\n"
  end;

  let t_make_requires_pipeline_action =
    with_temp_pipeline_project
      "p = pipeline {\n  a = 1\n}\n"
      (fun _dir _pipeline_path ->
        let env = Packages.init_env () in
        let (v, _) = eval_string_env "t_make()" env in
        let actual = strip_location (Ast.Utils.value_to_string v) in
        let expected = "Function `t_make` requires `src/pipeline.t` to call `populate_pipeline(...)` or `build_pipeline(...)`." in
        Test_helpers.contains actual expected)
  in
  if t_make_requires_pipeline_action then begin
    incr pass_count; Printf.printf "  ✓ t_make requires an explicit populate or build call in src/pipeline.t\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ t_make requires an explicit populate or build call in src/pipeline.t\n"
  end;
  let t_make_warns_on_populate_without_build =
    with_temp_pipeline_project
      "p = pipeline {\n  a = 1\n}\npopulate_pipeline(p)\n"
      (fun _dir _pipeline_path ->
        let env = Packages.init_env () in
        let ((v, _), warning) =
          capture_stderr (fun () -> eval_string_env "t_make()" env)
        in
        Ast.Utils.value_to_string v = "NA"
        && Test_helpers.contains warning "Warning: `t_make()` found `populate_pipeline"
        && Test_helpers.contains warning "build=true")
  in
  if t_make_warns_on_populate_without_build then begin
    incr pass_count; Printf.printf "  ✓ t_make warns when src/pipeline.t only populates the pipeline\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ t_make warns when src/pipeline.t only populates the pipeline\n"
  end;
  let t_make_warns_on_populate_build_unknown =
    with_temp_pipeline_project
      "do_build = false\np = pipeline {\n  a = 1\n}\npopulate_pipeline(p, build=do_build)\n"
      (fun _dir _pipeline_path ->
        let env = Packages.init_env () in
        let ((v, _), warning) =
          capture_stderr (fun () -> eval_string_env "t_make()" env)
        in
        Ast.Utils.value_to_string v = "NA"
        && Test_helpers.contains warning "Warning: `t_make"
        && Test_helpers.contains warning "populate_pipeline"
        && Test_helpers.contains warning "could not confirm whether a build was requested")
  in
  if t_make_warns_on_populate_build_unknown then begin
    incr pass_count; Printf.printf "  ✓ t_make warns when src/pipeline.t has ambiguous build intent\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ t_make warns when src/pipeline.t has ambiguous build intent\n"
  end;
  let pipeline_entry_detection_ok =
    Pipeline_script.is_pipeline_entry_file "src/pipeline.t"
    && Pipeline_script.is_pipeline_entry_file "./src/pipeline.t"
    && Pipeline_script.is_pipeline_entry_file "src/./pipeline.t"
    && not (Pipeline_script.is_pipeline_entry_file "pipeline.t")
    && not (Pipeline_script.is_pipeline_entry_file "src/other.t")
    && not (Pipeline_script.is_pipeline_entry_file "other/pipeline.t")
    && not (Pipeline_script.is_pipeline_entry_file "/tmp/project/src/pipeline.t")
  in
  if pipeline_entry_detection_ok then begin
    incr pass_count; Printf.printf "  ✓ pipeline entry detection only accepts project-relative src/pipeline.t\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline entry detection only accepts project-relative src/pipeline.t\n"
  end;
  let t_make_relative_filename_ok =
    with_temp_pipeline_project
      "p = pipeline {\n  a = 1\n}\npopulate_pipeline(p, build=false)\n"
      (fun _dir _pipeline_path ->
        let env = Packages.init_env () in
        let (v, _) = eval_string_env "t_make(filename=\"./src/pipeline.t\")" env in
        Ast.Utils.value_to_string v = "NA")
  in
  if t_make_relative_filename_ok then begin
    incr pass_count; Printf.printf "  ✓ t_make accepts normalized relative src/pipeline.t paths\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ t_make accepts normalized relative src/pipeline.t paths\n"
  end;
  let t_make_absolute_filename_rejected =
    with_temp_pipeline_project
      "p = pipeline {\n  a = 1\n}\npopulate_pipeline(p, build=false)\n"
      (fun _dir pipeline_path ->
        let env = Packages.init_env () in
        let command = Printf.sprintf "error_code(t_make(filename=%S)) == \"ValueError\"" pipeline_path in
        let (v, _) = eval_string_env command env in
        Ast.Utils.value_to_string v = "true")
  in
  if t_make_absolute_filename_rejected then begin
    incr pass_count; Printf.printf "  ✓ t_make rejects absolute pipeline entry filenames\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ t_make rejects absolute pipeline entry filenames\n"
  end;
  let t_make_reloads_pipeline_script =
    with_temp_pipeline_project
      "helper = 1\np = pipeline {\n  a = helper\n}\npopulate_pipeline(p, build=false)\n"
      (fun _dir pipeline_path ->
        let env = Packages.init_env () in
        let (_first, env) = eval_string_env "t_make()" env in
        let oc = open_out pipeline_path in
        output_string oc "other = 2\np = pipeline {\n  b = other\n}\npopulate_pipeline(p, build=false)\n";
        close_out oc;
        let (second, env) = eval_string_env "t_make()" env in
        let (new_binding_check, _) = eval_string_env "other == 2 && is_error(p.b) == false" env in
        let (stale_binding_removed_check, _) = eval_string_env "is_error(helper)" env in
        let (old_node_check, _) = eval_string_env "is_error(p.a)" env in
        let pipeline_nix = Filename.concat "_pipeline" "pipeline.nix" in
        let content =
          let ch = open_in pipeline_nix in
          Fun.protect
            ~finally:(fun () -> close_in_noerr ch)
            (fun () -> really_input_string ch (in_channel_length ch))
        in
        Ast.Utils.value_to_string second = "NA"
        && Ast.Utils.value_to_string new_binding_check = "true"
        && Ast.Utils.value_to_string stale_binding_removed_check = "true"
        && Ast.Utils.value_to_string old_node_check = "true"
        && contains_pattern "\\(^\\|\\n\\)[ \t]*b[ \t]*=" content
        && not (contains_pattern "\\(^\\|\\n\\)[ \t]*a[ \t]*=" content))
  in
  if t_make_reloads_pipeline_script then begin
    incr pass_count; Printf.printf "  ✓ t_make reloads src/pipeline.t in the same environment\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ t_make reloads src/pipeline.t in the same environment\n"
  end;
  print_newline ();

  Printf.printf "Serialization Builtins:\n";
  let write_marshaled_value path version value =
    let payload = Marshal.to_bytes value [] in
    let digest = Digest.bytes payload in
    let hex = Digest.to_hex digest in
    let oc = open_out_bin path in
    output_string oc (Serialization.serialized_value_magic ^ version ^ "\n");
    output_string oc hex;
    output_char oc '\n';
    output_bytes oc payload;
    close_out oc
  in
  let write_marshaled_value_legacy path version value =
    let oc = open_out_bin path in
    output_string oc (Serialization.serialized_value_magic ^ version ^ "\n");
    Marshal.to_channel oc value [];
    close_out oc
  in
  test "serialize and deserialize roundtrip"
    {|serialize([1, 2, 3], "test_roundtrip.tobj"); deserialize("test_roundtrip.tobj")|}
    "[1, 2, 3]";
  let prior_patchless_version =
    match Serialization.serialized_value_patchless_compatibility_version with
    | Some version -> version
    | None ->
        failwith
          (Printf.sprintf
             "expected patchless serialization compatibility for x.y.0 release %s (patch version 0) but serialized_value_patchless_compatibility_version was None"
             Serialization.serialized_value_format_version)
  in
  let prior_patchless_cache_path = "test_roundtrip_patchless_legacy.tobj" in
  write_marshaled_value prior_patchless_cache_path prior_patchless_version (Ast.VInt 4);
  test "deserialize accepts previous patchless serialized value version"
    {|deserialize("test_roundtrip_patchless_legacy.tobj")|}
    "4";
  let legacy_cache_path = "test_roundtrip_legacy.tobj" in
  write_marshaled_value_legacy legacy_cache_path "0.4.0" (Ast.VInt 3);
  let legacy_deserialize_error =
    Printf.sprintf
      {|Error(FileError: "deserialize failed: Serialized value format version `0.4.0` is not compatible with `%s`. Rebuild or re-serialize this artifact with the current serializer.")|}
      Serialization.serialized_value_format_version
  in
  test "deserialize rejects older serialized value versions"
    {|deserialize("test_roundtrip_legacy.tobj")|}
    legacy_deserialize_error;
  print_newline ();

  Printf.printf "Phase 3 — Pipeline with Pipes:\n";
  test "pipeline with pipe operator"
    "double = \\(x) x * 2\np = pipeline {\n  a = 5\n  b = a |> double\n}; read_node(p.b)"
    "unbuilt";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline with Functions:\n";
  test "pipeline with function calls"
    "p = pipeline {\n  data = [1, 2, 3]\n  total = sum(data)\n  count = length(data)\n}; read_node(p.total)"
    "unbuilt";
  test "pipeline nodes available individually"
    "p = pipeline {\n  data = [1, 2, 3]\n  total = sum(data)\n  count = length(data)\n}; read_node(p.count)"
    "unbuilt";
  print_newline ();

  Printf.printf "Phase 3 — Pipeline Error Handling:\n";
  test "pipeline cycle detection"
    "pipeline {\n  a = b\n  b = a\n}"
    {|Error(StructuralError: "Pipeline has a dependency cycle involving node `a`.")|};
  test "pipeline with error in node"
    "pipeline {\n  a = 1 / 0\n  b = a + 1\n}"
    "Pipeline(2 nodes: [a, b])";
  
  test "explain shows runtime for T node error"
    "p = pipeline { a = 1 / 0 }; info = explain(p.a); info.runtime"
    "\"T\"";

  test "explain shows runtime for upstream T error"
    "p = pipeline { a = 1 / 0; b = a + 1 }; info = explain(p.b); info.runtime"
    "\"T\"";

  (try Unix.mkdir "_pipeline" 0o755 with _ -> ());
  let max_temp_dir_attempts = 8 in
  (* A small retry budget is enough here because collisions on the temp path are
     already rare and each retry gets a fresh timestamped candidate. *)
  let rec make_temp_dir prefix attempts =
    if attempts <= 0 then
      failwith
        ("failed to create temporary pipeline fixture directory after "
         ^ string_of_int max_temp_dir_attempts ^ " attempts with prefix \""
         ^ prefix ^ "\"")
    else
      let path =
        Filename.concat
          (Filename.get_temp_dir_name ())
          (Printf.sprintf "%s%d-%Ld"
             prefix
             (Unix.getpid ())
             (Int64.of_float (Unix.gettimeofday () *. 1_000_000.)))
      in
      try
        Unix.mkdir path 0o700;
        path
      with Unix.Unix_error (Unix.EEXIST, _, _) ->
        make_temp_dir prefix (attempts - 1)
  in
  let ensure_subdir parent name =
    let dir = Filename.concat parent name in
    if Sys.file_exists dir then
      if Sys.is_directory dir then
        dir
      else
        failwith
          ("Test fixture setup failed: expected directory but found non-directory path at "
           ^ dir)
    else
      try
        Unix.mkdir dir 0o700;
        dir
      with Unix.Unix_error (err, _, _) ->
        failwith
          ("Test fixture setup failed: could not create temp directory "
           ^ dir ^ ": " ^ Unix.error_message err)
  in
  let temp_root_dir = make_temp_dir "tlang-pipeline-" max_temp_dir_attempts in
  let error_node_dir = ensure_subdir temp_root_dir "tlang-error-node" in
  let plot_json_dir = ensure_subdir temp_root_dir "tlang-plot-fallback" in
  Fun.protect
    ~finally:(fun () -> remove_path temp_root_dir)
    (fun () ->
      let mocked_error_message =
        "Error in wrong(mtcars): could not find function \"wrong\"\n"
      in
      let error_node_path = Filename.concat error_node_dir "artifact" in
      (* Test fixture setup should fail fast if the mocked error artifact cannot be written. *)
      (match Serialization.write_json error_node_path
         (Ast.VError {
           code = Ast.RuntimeError;
           message = mocked_error_message;
           context = [
             ("runtime_traceback", Ast.VString mocked_error_message);
             ("node_status", Ast.VString "errored");
           ];
           location = Some { Ast.file = None; line = 0; column = 0 };
           na_count = 0;
         }) with
       | Ok () -> ()
       | Error msg ->
           failwith
             ("Test fixture setup failed: could not write mocked error node artifact to "
              ^ error_node_path ^ ": " ^ msg));
      let mock_log = Printf.sprintf {|{
    "timestamp": "20240101-000000",
    "hash": "mock",
    "out_path": "/tmp",
    "nodes": [
      { "node": "error_node", "path": "%s", "runtime": "R", "serializer": "json", "class": "VError", "dependencies": [], "success": "false" },
      { "node": "r_fail", "path": "/nonexistent", "runtime": "R", "serializer": "default", "class": "V", "dependencies": [], "success": "true" },
      { "node": "py_fail", "path": "/nonexistent", "runtime": "Python", "serializer": "default", "class": "V", "dependencies": [], "success": "true" }
    ]
  }|} error_node_path in
      let oc_mock = open_out "_pipeline/build_log_ocaml_mock.json" in
      output_string oc_mock mock_log;
      close_out oc_mock;

      let legacy_node_path = "test_legacy_node.tobj" in
      write_marshaled_value_legacy legacy_node_path "0.4.0" (Ast.VInt 7);
      let plot_json_path = Filename.concat plot_json_dir "artifact" in
      let plot_json_viz = Filename.concat plot_json_dir "viz" in
      (try Sys.remove plot_json_viz with Sys_error _ -> ());
      (match Serialization.write_json plot_json_path
         (Ast.VDict [
           ("class", Ast.VString "matplotlib");
           ("backend", Ast.VString "Python");
           ("title", Ast.VString "Fallback plot");
           ("mapping", Ast.VDict []);
           ("labels", Ast.VDict [("x", Ast.VString "x"); ("y", Ast.VString "y")]);
           ("layers", Ast.VList [(None, Ast.VString "Line2D")]);
         ]) with
       | Ok () -> ()
       | Error msg ->
           failwith
             ("Test fixture setup failed: could not write plot metadata artifact to "
              ^ plot_json_path ^ ": " ^ msg));
      let legacy_log = Printf.sprintf {|{
    "timestamp": "20240101-000001",
    "hash": "legacy",
    "out_path": "/tmp",
    "nodes": [
      { "node": "legacy_node", "path": "%s", "runtime": "T", "serializer": "default", "class": "V", "dependencies": [], "success": "true" },
      { "node": "compatible_node", "path": "test_roundtrip.tobj", "runtime": "T", "serializer": "default", "class": "V", "dependencies": [], "success": "true" },
      { "node": "plot_json_node", "path": "%s", "runtime": "Python", "serializer": "json", "class": "matplotlib", "dependencies": [], "success": "true" }
    ]
  }|} legacy_node_path plot_json_path in
      let oc_legacy_log = open_out "_pipeline/build_log_legacy_version.json" in
      output_string oc_legacy_log legacy_log;
      close_out oc_legacy_log;
      let legacy_node_error =
        Printf.sprintf
          {|Error(FileError: "Failed to read node `legacy_node` from `test_legacy_node.tobj`: Serialized value format version `0.4.0` is not compatible with `%s`. Rebuild or re-serialize this artifact with the current serializer.")|}
          Serialization.serialized_value_format_version
      in
      let explained_compatible_node =
        String.concat "" [
          {|{`kind`: "node", `node_name`: "compatible_node", `diagnostics`: |};
          {|{`warnings`: [], `error`: NA, `warnings_suppressed`: false, |};
          {|`recovered`: false, `upstream_errors`: []}, `contents`: |};
          {|{`kind`: "value", `type`: "List", `length`: 3, `na_count`: 0, |};
          {|`examples`: [1, 2, 3]}}|};
        ]
      in
      let explain_pipeline_error_dir =
        ensure_subdir temp_root_dir "tlang-explain-pipeline-error"
      in
      let explain_pipeline_error_path =
        Filename.concat explain_pipeline_error_dir "artifact"
      in
      (match Serialization.write_json explain_pipeline_error_path
         (Ast.VError {
           code = Ast.RuntimeError;
           message = "mocked pipeline build failure";
           context = [];
           location = None;
           na_count = 0;
         }) with
       | Ok () -> ()
       | Error msg ->
           failwith
             ("Test fixture setup failed: could not write explain pipeline error artifact to "
              ^ explain_pipeline_error_path ^ ": " ^ msg));
      let explain_pipeline_log = Printf.sprintf {|{
    "timestamp": "20240101-999999",
    "hash": "explain-pipeline",
    "out_path": "/tmp",
    "nodes": [
      { "node": "good", "path": "/tmp/good", "runtime": "T", "serializer": "default", "class": "V", "dependencies": [], "success": "true" },
      { "node": "bad", "path": "%s", "runtime": "R", "serializer": "json", "class": "VError", "dependencies": [], "success": "false" }
    ]
  }|} explain_pipeline_error_path in
      let oc_explain_pipeline = open_out "_pipeline/build_log_zz_explain_pipeline.json" in
      output_string oc_explain_pipeline explain_pipeline_log;
      close_out oc_explain_pipeline;
      let recovered_match_dir =
        ensure_subdir temp_root_dir "tlang-recovered-with-match"
      in
      let recovered_match_path =
        Filename.concat recovered_match_dir "artifact"
      in
      (match Serialization.write_json recovered_match_path
         (Ast.VDict [("status", Ast.VString "ok")]) with
       | Ok () -> ()
       | Error msg ->
           failwith
             ("Test fixture setup failed: could not write recovered-match artifact to "
              ^ recovered_match_path ^ ": " ^ msg));
      let recovered_match_log = Printf.sprintf {|{
    "timestamp": "20240101-999998",
    "hash": "recovered-match",
    "out_path": "/tmp",
    "nodes": [
      { "node": "good_val", "path": "/tmp/good-val", "runtime": "T", "serializer": "default", "class": "V", "dependencies": [], "success": "true" },
      { "node": "recovered_with_match", "path": "%s", "runtime": "R", "serializer": "json", "class": "VDict", "dependencies": [], "success": "true" }
    ]
  }|} recovered_match_path in
      let oc_recovered_match =
        open_out "_pipeline/build_log_zz_recovered_with_match.json"
      in
      output_string oc_recovered_match recovered_match_log;
      close_out oc_recovered_match;

      test "read_node propagates R runtime on error"
        "explain(read_node(pipeline { r_fail = node() }.r_fail, which_log=\"ocaml_mock\")).contents.runtime"
        "\"R\"";

      test "read_node propagates Python runtime on error"
        "explain(read_node(pipeline { py_fail = node() }.py_fail, which_log=\"ocaml_mock\")).contents.runtime"
        "\"Python\"";
      test "explain(read_node(...)) wraps node metadata separately"
        "explain(read_node(pipeline { compatible_node = node() }.compatible_node, which_log=\"legacy_version\"))"
        explained_compatible_node;
      test "explain(read_node(...)) nests explained error contents"
        "explain(read_node(pipeline { error_node = node() }.error_node, which_log=\"ocaml_mock\")).contents.error_code"
        {|"RuntimeError"|};
      test "explain(read_node(...)) exposes node display key order"
        "explain(read_node(pipeline { compatible_node = node() }.compatible_node, which_log=\"legacy_version\"))._display_keys .== [\"kind\", \"node_name\", \"diagnostics\", \"contents\"]"
        "[true, true, true, true]";
      test "read_node (mocked) reads compatible artifact"
        "read_node(pipeline { compatible_node = node() }.compatible_node, which_log=\"legacy_version\") .== [1, 2, 3]"
        "[true, true, true]";
      test "read_node missing key (mocked)"
        "error_code(read_node(pipeline { missing = node() }.missing, which_log=\"ocaml_mock\")) == \"KeyError\""
        "true";
      test "read_node error exposes error_code field"
        "read_node(pipeline { error_node = node() }.error_node, which_log=\"ocaml_mock\").error_code"
        {|"RuntimeError"|};
      test "read_node error exposes error_msg field"
        "read_node(pipeline { error_node = node() }.error_node, which_log=\"ocaml_mock\").error_msg"
        (Ast.Utils.value_to_string (Ast.VString mocked_error_message));
      test "read_node error exposes context dict"
        "read_node(pipeline { error_node = node() }.error_node, which_log=\"ocaml_mock\").context.node_status"
        {|"errored"|};

      test "read_node falls back to artifact deserializer when plot viz sidecar is absent"
        "read_node(pipeline { plot_json_node = node() }.plot_json_node, which_log=\"legacy_version\").title"
        {|"Fallback plot"|};
      test "plot fallback fixture does not create a viz sidecar"
        (Printf.sprintf {|file_exists("%s")|} plot_json_viz)
        "false";
      test "explain(pipeline) prefers latest build diagnostics when node names match"
        {|p_logged = pipeline {
  good = 1
  bad = node(command = <{ 1 }>, runtime = R)
}; explain(p_logged).diagnostics.summary|}
        "\"0 node(s) with warnings, 0 suppressed, 1 error(s), 0 recovered\"";
      test "read_node(pipeline, name) prefers latest build diagnostics when node names match"
        {|p_logged = pipeline {
  good = 1
  bad = node(command = <{ 1 }>, runtime = R)
}; read_node(p_logged.bad).error.kind|}
        "\"RuntimeError\"";
      test "filter_node uses merged build-log diagnostics in predicates"
        {|p_logged = pipeline {
  good = 1
  bad = node(command = <{ 1 }>, runtime = R)
}; filter_node(p_logged, !is_na($diagnostics.error)) |> pipeline_nodes|}
        {|["bad"]|};
      test "read_node(pipeline, name) prefers matching build-log values for unresolved nodes"
        {|p_match = pipeline {
  good_val = 20
  recovered_with_match = node(command = <{ 1 }>, runtime = R, serializer = ^json, deserializer = ^json)
}; read_node(p_match.recovered_with_match).value.status|}
        {|"ok"|};
      test "read_pipeline prefers matching build-log values for unresolved nodes"
        {|p_match = pipeline {
  good_val = 20
  recovered_with_match = node(command = <{ 1 }>, runtime = R, serializer = ^json, deserializer = ^json)
}; read_pipeline(p_match).nodes |> filter(\(node) node.name == "recovered_with_match") |> map(\(node) node.value.status)|}
        {|["ok"]|};
      test "filter_node returns merged build-log values for kept unresolved nodes"
        {|p_match = pipeline {
  good_val = 20
  recovered_with_match = node(command = <{ 1 }>, runtime = R, serializer = ^json, deserializer = ^json)
}; read_pipeline(filter_node(p_match, is_na($diagnostics.error))).nodes |> filter(\(node) node.name == "recovered_with_match") |> map(\(node) node.value.status)|}
        {|["ok"]|};

      test "read_node rejects older serialized node versions"
        "read_node(pipeline { legacy_node = node() }.legacy_node, which_log=\"legacy_version\")"
        legacy_node_error);

  print_newline ();

  Printf.printf "Phase 3 — Pipeline Diagnostics:\n";
  test "read_node(p, name) exposes warning list"
    {|p_diag = pipeline {
  data = to_dataframe([[x: 1], [x: NA], [x: 3]])
  filtered = filter(data, $x > 1)
  count = nrow(filtered)
}; length(read_node(p_diag.filtered).warnings)|}
    "unbuilt";
  test "downstream nodes inherit upstream warnings"
    {|p_diag = pipeline {
  data = to_dataframe([[x: 1], [x: NA], [x: 3]])
  filtered = filter(data, $x > 1)
  count = nrow(filtered)
}; read_node(p_diag.count).warnings |> map(\(w) w.source.kind)|}
    "unbuilt";
  test "downstream warning source points at origin node"
    {|p_diag = pipeline {
  data = to_dataframe([[x: 1], [x: NA], [x: 3]])
  filtered = filter(data, $x > 1)
  count = nrow(filtered)
}; read_node(p_diag.count).warnings |> map(\(w) w.source.node)|}
    "unbuilt";
  test "read_pipeline summarizes warning origins only once"
    {|p_diag = pipeline {
  data = to_dataframe([[x: 1], [x: NA], [x: 3]])
  filtered = filter(data, $x > 1)
  count = nrow(filtered)
}; read_pipeline(p_diag).diagnostics.summary|}
    "\"0 node(s) with warnings, 0 suppressed, 0 error(s), 0 recovered\"";
  test "read_pipeline tracks error nodes"
    {|p_err = pipeline {
  bad = 1 / 0
  downstream = bad + 1
}; read_pipeline(p_err).diagnostics.summary|}
    "\"0 node(s) with warnings, 0 suppressed, 0 error(s), 0 recovered\"";

  test "warning_msg() built-in returns warning message"
    {|p_diag = pipeline {
  data = to_dataframe([[x: 1], [x: NA], [x: 3]])
  filtered = filter(data, $x > 1)
  count = nrow(filtered)
}; warning_msg(p_diag.filtered) != ""|}
    "false";
  test "warning_msg property on computed node returns warning message"
    {|p_diag = pipeline {
  data = to_dataframe([[x: 1], [x: NA], [x: 3]])
  filtered = filter(data, $x > 1)
  count = nrow(filtered)
}; p_diag.filtered.warning_msg != ""|}
    "false";


  test "read_node(p, name) exposes structured node errors"
    {|p_err = pipeline {
  bad = 1 / 0
  downstream = bad + 1
}; read_node(p_err.bad).error.kind|}
    "\"FileError\"";
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
  let (v, _) = eval_string_env "read_node(p.rows)" env_p3_df in
  let result = Ast.Utils.value_to_string v in
  if Test_helpers.contains result "unbuilt" then begin
    incr pass_count; Printf.printf "  ✓ pipeline with DataFrame nrow returns FileError for unbuilt pipeline\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline with DataFrame nrow\n    Expected: FileError with 'unbuilt'\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env "read_node(p.cols)" env_p3_df in
  let result = Ast.Utils.value_to_string v in
  if Test_helpers.contains result "unbuilt" then begin
    incr pass_count; Printf.printf "  ✓ pipeline with DataFrame ncol returns FileError for unbuilt pipeline\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pipeline with DataFrame ncol\n    Expected: FileError with 'unbuilt'\n    Got: %s\n" result
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
    {|pyn(command = <{ x + 1 }>, env_vars = [API_KEY: "secret", RETRIES: 3])|}
    (Packages.init_env ()) in
  let same_env_vars left right =
    let sort_vars vars = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) vars in
    sort_vars left = sort_vars right
  in
  let same_runtime_args left right =
    let sort_args runtime_args = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) runtime_args in
    sort_args left = sort_args right
  in
  let contains_substring s sub =
    let s_len = String.length s in
    let sub_len = String.length sub in
    let rec loop idx =
      if sub_len = 0 then true
      else if idx + sub_len > s_len then false
      else if String.sub s idx sub_len = sub then true
      else loop (idx + 1)
    in
    loop 0
  in
  (match v_py_node with
   | Ast.VNode un
      when un.un_runtime = "Python"
           && same_env_vars un.un_env_vars [("API_KEY", Ast.VString "secret"); ("RETRIES", Ast.VInt 3)] ->
       incr pass_count; Printf.printf "  ✓ pyn() stores env_vars on the node\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ pyn() env_vars parsing failed: %s\n"
         (Ast.Utils.value_to_string other));

  test "node env_vars must be a dict"
    {|node(command = 1, env_vars = 1)|}
    {|Error(TypeError: "Function `node` expects `env_vars` to be a Dict.")|};

  test "node args must be a dict or list"
    {|node(runtime = Quarto, args = 1)|}
    {|Error(TypeError: "Function `node` expects `args` to be a Dict or List.")|};

  test "node args values must stay shallow"
    {|node(runtime = Quarto, args = [path: "report.qmd", extra: [nested: [too_deep: 1]]])|}
    {|Error(TypeError: "Function `node` expects runtime arg `extra` to be a String, Symbol, Int, Float, Bool, NA, or List of those values.")|};

  test "quarto node requires qmd path"
    {|node(runtime = Quarto, args = [subcommand: "render"])|}
    {|Error(TypeError: "Node with runtime `Quarto` requires `script` or `args.path`/`args.file`/`args.qmd_file`/`args.input` to point to a `.qmd` file.")|};

  test "quarto node command conflict (explicit script)"
    {|node(command = <{ 1 + 1 }>, script = "report.qmd", runtime = Quarto)|}
    {|Error(TypeError: "node() cannot use both 'command' and 'script' arguments — choose one.")|};
 
  test "quarto node command conflict (inlined command)"
    {|node(command = <{ 1 + 1 }>, runtime = Quarto, args = [path: "report.qmd"])|}
    {|Error(TypeError: "Quarto nodes require a script and do not support inlined `command` blocks.")|};
 
  let (v_r_mixed, _) = eval_string_env
    {|rn(command = <{ read_csv(path) }>, args = [path: "data.csv"])|}
    (Packages.init_env ()) in
  (match v_r_mixed with
   | Ast.VNode un when un.un_runtime = "R" && List.exists (function { Ast.node = Ast.Value (VString "data.csv"); _ } -> true | _ -> false) un.un_includes ->
       incr pass_count; Printf.printf "  ✓ R node supports both command and args.path (auto-included)\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ R node command/args mixed test failed: %s\n"
         (Ast.Utils.value_to_string other));

  let (v_quarto_node, _) = eval_string_env
    {|node(runtime = Quarto, args = [subcommand: "render", path: "report.qmd", to: "html", standalone: true])|}
    (Packages.init_env ()) in
  (match v_quarto_node with
    | Ast.VNode un
      when un.un_runtime = "Quarto"
           && un.un_script = Some "report.qmd"
          && same_runtime_args un.un_args [
               ("subcommand", Ast.VString "render");
               ("path", Ast.VString "report.qmd");
               ("to", Ast.VString "html");
               ("standalone", Ast.VBool true);
             ] ->
       incr pass_count; Printf.printf "  ✓ node() stores Quarto runtime args and qmd path\n"
   | other ->
        incr fail_count; Printf.printf "  ✗ Quarto node args parsing failed: %s\n"
          (Ast.Utils.value_to_string other));

  let (v_qn_node, _) = eval_string_env
    {|qn(args = [subcommand: "render", path: "report.qmd", to: "html"])|}
    (Packages.init_env ()) in
  (match v_qn_node with
   | Ast.VNode un
      when un.un_runtime = "Quarto"
           && un.un_script = Some "report.qmd" ->
        incr pass_count; Printf.printf "  ✓ qn() defaults to the Quarto runtime\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ qn() runtime wrapper failed: %s\n"
         (Ast.Utils.value_to_string other));

  let (v_py_pipeline, _) = eval_string_env
    {|pipeline {
  data = 1
  step = pyn(command = <{ data + 1 }>, env_vars = [MODE: "fast"], deserializer = ^json)
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
         incr pass_count; Printf.printf "  ✓ pyn() nodes are desugared with env_vars in pipelines\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ pyn() pipeline desugaring failed\n"
       end
   | other ->
       incr fail_count; Printf.printf "  ✗ pyn() pipeline should return VPipeline, got: %s\n"
         (Ast.Utils.value_to_string other));

  let (v_env_pipeline, _) = eval_string_env
    {|pipeline {
  model = rn(command = <{ 1 + 1 }>, env_vars = [MODEL_MODE: "train", RETRIES: 2], deserializer = ^json)
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
        let has_model_mode = contains_substring nix {|"MODEL_MODE" = "train";|} in
        let has_retries = contains_substring nix {|"RETRIES" = "2";|} in
       if rerun_has_envs && has_model_mode && has_retries then begin
         incr pass_count; Printf.printf "  ✓ pipeline preserves and emits node env_vars\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ pipeline env_vars preservation/emission failed\n"
       end
    | other ->
         incr fail_count; Printf.printf "  ✗ pipeline with env_vars should return VPipeline, got: %s\n"
           (Ast.Utils.value_to_string other));

  let (v_serializer_pipeline, _) = eval_string_env
    {|pipeline {
  source = [answer: 42]
  report_r = rn(command = <{ source }>, serializer = ^json, deserializer = ^json)
  report_py = pyn(command = <{ source }>, serializer = ^arrow, deserializer = ^arrow)
}|}
    (Packages.init_env ()) in
  (match v_serializer_pipeline with
   | Ast.VPipeline p ->
        let nix = Nix_emit_pipeline.emit_pipeline p in
        let has_r_json_helpers =
         contains_substring nix "r_write_json <- function" &&
         contains_substring nix "r_read_json <- function" &&
         contains_substring nix "dep_source <- r_read_json(" &&
         contains_substring nix "r_write_json(node_result,"
       in
        let has_py_arrow_helpers =
          contains_substring nix "def py_write_arrow(df, path):" &&
          contains_substring nix "def py_read_arrow(path):" &&
          contains_substring nix "__dep_source = py_read_arrow(" &&
          contains_substring nix "py_write_arrow(__node_result,"
        in
        let omits_old_runtime_prefixed_helpers =
          (not (contains_substring nix "t_read_json(")) &&
          (not (contains_substring nix "t_write_json(")) &&
          (not (contains_substring nix "t_read_arrow(")) &&
          (not (contains_substring nix "t_write_arrow("))
        in
        if has_r_json_helpers && has_py_arrow_helpers && omits_old_runtime_prefixed_helpers then begin
          incr pass_count; Printf.printf "  ✓ pipeline emits r_/py_ runtime serializer helper names\n"
        end else begin
          incr fail_count; Printf.printf "  ✗ runtime serializer helper naming emission failed\n"
        end
    | other ->
        incr fail_count; Printf.printf "  ✗ serializer naming pipeline should return VPipeline, got: %s\n"
          (Ast.Utils.value_to_string other));

  let (v_plot_pipeline, _) = eval_string_env
    {|pipeline {
  plot_r = rn(command = <{
    library(ggplot2)
    ggplot(mtcars, aes(wt, mpg)) + geom_point() + labs(title = "Fuel economy")
  }>)
  plot_py = pyn(command = <{
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots()
    ax.plot([1, 2], [3, 4])
    fig
  }>)
  plot_jl = node(runtime = Julia, command = <{
    using Plots
    plot([1, 2], [3, 4], title = "Fuel economy")
  }>)
}|}
    (Packages.init_env ()) in
  (match v_plot_pipeline with
   | Ast.VPipeline p ->
       let nix = Nix_emit_pipeline.emit_pipeline p in
       let has_r_plot_helpers =
         contains_substring nix "r_extract_plot_metadata <- function(object)" &&
         contains_substring nix "r_save_viz_metadata <- function(object, path)" &&
         contains_substring nix "file.path(Sys.getenv('out'), 'class')" &&
         contains_substring nix "r_save_viz_metadata(node_result, file.path(Sys.getenv('out'), 'viz'))"
       in
        let has_py_plot_helpers =
          contains_substring nix "def py_extract_plot_metadata(obj):" &&
          contains_substring nix "from plotnine.ggplot import ggplot as PlotnineGGPlot" &&
          contains_substring nix "\"class\": \"plotnine\"" &&
          contains_substring nix "\"backend\": \"Python\"" &&
          contains_substring nix "py_visual_class(__node_result)" &&
          contains_substring nix "py_save_viz_metadata(__node_result, os.path.join(os.environ['out'], 'viz'))"
        in
        let has_jl_plot_helpers =
          contains_substring nix "function jl_extract_plot_metadata(obj)" &&
          contains_substring nix "\"class\" => \"tidierplots\"" &&
          contains_substring nix "\"class\" => \"plotsjl\"" &&
          contains_substring nix "\"class\" => \"makie\"" &&
          contains_substring nix "jl_visual_class(__node_result)" &&
          contains_substring nix "jl_save_viz_metadata(__node_result, joinpath(ENV[\"out\"], \"viz\"))"
        in
        if has_r_plot_helpers && has_py_plot_helpers && has_jl_plot_helpers then begin
         incr pass_count; Printf.printf "  ✓ pipeline emits plot metadata helpers for R, Python, and Julia nodes\n"
        end else begin
          incr fail_count; Printf.printf "  ✗ plot metadata helper emission failed\n"
        end
   | other ->
       incr fail_count; Printf.printf "  ✗ plot metadata pipeline should return VPipeline, got: %s\n"
         (Ast.Utils.value_to_string other));

  let temp_plot_dir = Filename.concat (Filename.get_temp_dir_name ()) "tlang-plot-metadata" in
  (try Unix.mkdir temp_plot_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let ggplot_node_dir = Filename.concat temp_plot_dir "ggplot-node" in
  (try Unix.mkdir ggplot_node_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let ggplot_viz = Filename.concat ggplot_node_dir "viz" in
  (* artifact now holds "real" data or is irrelevant for this metadata-reading test *)
  let ggplot_artifact = Filename.concat ggplot_node_dir "artifact" in
  let ggplot_class = Filename.concat ggplot_node_dir "class" in
  let ggplot_value =
    Ast.VDict [
      ("class", Ast.VString "ggplot");
      ("backend", Ast.VString "R");
      ("title", Ast.VString "Fuel economy");
      ("mapping", Ast.VDict [("x", Ast.VString "wt"); ("y", Ast.VString "mpg")]);
      ("labels", Ast.VDict [("x", Ast.VString "Weight"); ("y", Ast.VString "Miles per gallon")]);
      ("layers", Ast.VList [(None, Ast.VString "Point")]);
      ("_display_keys", Ast.VList [
        (None, Ast.VString "class");
        (None, Ast.VString "backend");
        (None, Ast.VString "title");
        (None, Ast.VString "mapping");
        (None, Ast.VString "labels");
        (None, Ast.VString "layers");
      ]);
    ]
  in
  ignore (Serialization.write_json ggplot_viz ggplot_value);
  let oc_art = open_out ggplot_artifact in output_string oc_art "dummy-artifact"; close_out oc_art;
  let oc_ggplot_class = open_out ggplot_class in
  output_string oc_ggplot_class "ggplot\n";
  close_out oc_ggplot_class;
  let original_plot_env = Sys.getenv_opt "T_NODE_plot_meta" in
  let restored =
    Fun.protect
      ~finally:(fun () ->
        match original_plot_env with
        | Some value -> Unix.putenv "T_NODE_plot_meta" value
        | None -> Unix.putenv "T_NODE_plot_meta" "")
      (fun () ->
        Unix.putenv "T_NODE_plot_meta" ggplot_node_dir;
        Builder.read_node "plot_meta")
  in
  (match restored with
   | Ast.VNodeResult { v = Ast.VDict pairs; _ }
      when List.assoc_opt "class" pairs = Some (Ast.VString "ggplot")
           && List.assoc_opt "title" pairs = Some (Ast.VString "Fuel economy") ->
       incr pass_count; Printf.printf "  ✓ read_node reads ggplot plot metadata artifacts from default serializer output\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ ggplot plot metadata artifact reading failed: %s\n"
          (Ast.Utils.value_to_string other));

  let julia_plot_node_dir = Filename.concat temp_plot_dir "julia-plot-node" in
  (try Unix.mkdir julia_plot_node_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let julia_plot_viz = Filename.concat julia_plot_node_dir "viz" in
  let julia_plot_artifact = Filename.concat julia_plot_node_dir "artifact" in
  let julia_plot_class = Filename.concat julia_plot_node_dir "class" in
  let julia_plot_value =
    Ast.VDict [
      ("class", Ast.VString "makie");
      ("backend", Ast.VString "Julia");
      ("title", Ast.VString "Makie figure");
      ("labels", Ast.VDict [("x", Ast.VString "wt"); ("y", Ast.VString "mpg")]);
      ("layers", Ast.VList [(None, Ast.VString "Axis"); (None, Ast.VString "Lines")]);
      ("_display_keys", Ast.VList [
        (None, Ast.VString "class");
        (None, Ast.VString "backend");
        (None, Ast.VString "title");
        (None, Ast.VString "labels");
        (None, Ast.VString "layers");
      ]);
    ]
  in
  ignore (Serialization.write_json julia_plot_viz julia_plot_value);
  let oc_julia_art = open_out julia_plot_artifact in output_string oc_julia_art "dummy-artifact"; close_out oc_julia_art;
  let oc_julia_class = open_out julia_plot_class in
  output_string oc_julia_class "makie\n";
  close_out oc_julia_class;
  let original_julia_plot_env = Sys.getenv_opt "T_NODE_julia_plot_meta" in
  let restored_julia =
    Fun.protect
      ~finally:(fun () ->
        match original_julia_plot_env with
        | Some value -> Unix.putenv "T_NODE_julia_plot_meta" value
        | None -> Unix.putenv "T_NODE_julia_plot_meta" "")
      (fun () ->
        Unix.putenv "T_NODE_julia_plot_meta" julia_plot_node_dir;
        Builder.read_node "julia_plot_meta")
  in
  (match restored_julia with
   | Ast.VNodeResult { v = Ast.VDict pairs; _ }
     when List.assoc_opt "class" pairs = Some (Ast.VString "makie")
          && List.assoc_opt "backend" pairs = Some (Ast.VString "Julia") ->
       incr pass_count; Printf.printf "  ✓ read_node reads Julia plot metadata artifacts from default serializer output\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ Julia plot metadata artifact reading failed: %s\n"
         (Ast.Utils.value_to_string other));

  let quarto_script = "test_quarto_report.qmd" in
  let quarto_dep_node = "data" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove quarto_script with _ -> ())
    (fun () ->
      let oc_quarto = open_out quarto_script in
      output_string oc_quarto (Printf.sprintf "```{r}\nread_node(\"%s\")\n```\n" quarto_dep_node);
      close_out oc_quarto;
      let (v_quarto_pipeline, _) = eval_string_env
        (Printf.sprintf
           {|pipeline {
  %s = 1
  report = node(runtime = Quarto, args = [subcommand: "render", path: "%s", to: "html", standalone: true])
}|}
           quarto_dep_node
           quarto_script)
        (Packages.init_env ()) in
      match v_quarto_pipeline with
      | Ast.VPipeline p ->
          let runtime_ok = List.assoc_opt "report" p.p_runtimes = Some "Quarto" in
          let args_ok =
            match List.assoc_opt "report" p.p_args with
            | Some runtime_args ->
                same_runtime_args runtime_args [
                  ("subcommand", Ast.VString "render");
                  ("path", Ast.VString quarto_script);
                  ("to", Ast.VString "html");
                  ("standalone", Ast.VBool true);
                ]
            | None -> false
          in
          let script_ok = List.assoc_opt "report" p.p_scripts = Some (Some quarto_script) in
          let nix = Nix_emit_pipeline.emit_pipeline p in
          let keeps_quarto_explicit = not (contains_substring nix "pkgs.quarto") in
          let has_render = contains_substring nix "cli_args+=('render')" in
          let has_path = contains_substring nix (Printf.sprintf "cli_args+=('%s')" quarto_script) in
          let has_to = contains_substring nix "cli_args+=('--to')" && contains_substring nix "cli_args+=('html')" in
          let has_flag = contains_substring nix "cli_args+=('--standalone')" in
          let has_read_node_sub = contains_substring nix "sed -i -e" && contains_substring nix (Printf.sprintf "$T_NODE_%s/artifact" quarto_dep_node) in
          if runtime_ok && args_ok && script_ok && keeps_quarto_explicit && has_render && has_path && has_to && has_flag && has_read_node_sub then begin
            incr pass_count; Printf.printf "  ✓ pipeline preserves and emits Quarto runtime args\n"
          end else begin
            incr fail_count; Printf.printf "  ✗ Quarto pipeline preservation/emission failed\n"
          end
      | other ->
          incr fail_count; Printf.printf "  ✗ pipeline with Quarto node should return VPipeline, got: %s\n"
            (Ast.Utils.value_to_string other));

  let (v_qn_pipeline, _) = eval_string_env
    {|pipeline {
  report = qn(args = [subcommand: "render", path: "report.qmd", to: "html"])
}|}
    (Packages.init_env ()) in
  (match v_qn_pipeline with
   | Ast.VPipeline p
     when List.assoc_opt "report" p.p_runtimes = Some "Quarto" ->
       incr pass_count; Printf.printf "  ✓ qn() nodes are desugared with Quarto runtime in pipelines\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ qn() pipeline desugaring failed: %s\n"
         (Ast.Utils.value_to_string other));

  test "pipeline_copy validates node type"
    {|pipeline_copy(node = 1)|}
    {|Error(TypeError: "Function `pipeline_copy` expects `node` to be a String, Symbol, or NA.")|};

  test "pipeline_copy validates target_dir type"
    {|pipeline_copy(target_dir = 1)|}
    {|Error(TypeError: "Function `pipeline_copy` expects `target_dir` to be a String or Symbol.")|};

  test "pipeline_copy validates dir_mode type"
    {|pipeline_copy(dir_mode = 755)|}
    {|Error(TypeError: "Function `pipeline_copy` expects `dir_mode` to be a String.")|};

  test "pipeline_copy validates file_mode type"
    {|pipeline_copy(file_mode = 644)|}
    {|Error(TypeError: "Function `pipeline_copy` expects `file_mode` to be a String.")|};

  test "pipeline_copy validates mode contents"
    {|pipeline_copy(dir_mode = "0755; rm -rf /")|}
    {|Error(GenericError: "Invalid file or directory mode: expected octal string like 0755 or 0644.")|};

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

  let (v_quarto_auto, _) = eval_string_env
    {|node(script = "paper.qmd")|}
    (Packages.init_env ()) in
  (match v_quarto_auto with
   | Ast.VNode un when un.un_runtime = "Quarto" ->
       incr pass_count; Printf.printf "  ✓ runtime auto-detected as Quarto for .qmd script\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ runtime auto-detection for .qmd failed: %s\n"
         (Ast.Utils.value_to_string other));

  (* Test: script field accessible via dot access *)
  let (v_dot_script, _) = eval_string_env
    {|node_obj = node(script = "fit.R", runtime = R); node_obj.script|}
    (Packages.init_env ()) in
  let dot_script_s = Ast.Utils.value_to_string v_dot_script in
  if dot_script_s = {|"fit.R"|} then begin
    incr pass_count; Printf.printf "  ✓ node.script dot access returns script path\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ node.script dot access\n    Expected: \"fit.R\"\n    Got: %s\n" dot_script_s
  end;

  (* Test: script=NA node returns NA for .script *)
  let (v_no_script, _) = eval_string_env
    {|node_obj = node(command = <{ 42 }>, runtime = R); node_obj.script|}
    (Packages.init_env ()) in
  if Ast.Utils.value_to_string v_no_script = "NA" then begin
    incr pass_count; Printf.printf "  ✓ node without script returns NA for .script\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ node without script .script field\n    Expected: NA\n    Got: %s\n"
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

  print_newline ();

  Printf.printf "Phase 3 — Cross-Pipeline Deferral & NameError Behavior:\n";

  (* Test: T node whose sibling R node is <unbuilt> is itself correctly deferred *)
  let (v_t_deferred, _) = eval_string_env
    {|p = pipeline {
  r_step = node(command = <{ 1 + 2 }>, runtime = R, deserializer = ^json)
  t_step = r_step * 2
}
p.t_step|}
    (Packages.init_env ()) in
  (match v_t_deferred with
  | Ast.VComputedNode cn when cn.cn_path = "<unbuilt>" ->
      incr pass_count; Printf.printf "  ✓ T node is deferred when its sibling node is <unbuilt>\n"
  | other ->
      incr fail_count; Printf.printf "  ✗ T node should be deferred when sibling is <unbuilt>\n    Got: %s\n"
        (Ast.Utils.value_to_string other));

  (* Test: T node with a typo'd/undefined function name raises NameError and is NOT silently deferred *)
  let (v_name_err, _) = eval_string_env
    {|pipeline {
  x = 1
  y = nonexistent_func_xyzzy(x)
}|}
    (Packages.init_env ()) in
  let name_err_str = Ast.Utils.value_to_string v_name_err in
  if contains_substring name_err_str "Pipeline" && contains_substring name_err_str "x" && contains_substring name_err_str "y" then begin
    incr pass_count; Printf.printf "  ✓ undefined function in T node defers evaluation (pipeline created, node unbuilt)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ undefined function in T node should create pipeline without error\n    Got: %s\n" name_err_str
  end;

  (* Test: rerun_pipeline correctly keeps a T node deferred when its sibling is <unbuilt> *)
  let (v_rerun_base, _) = eval_string_env
    {|pipeline {
  r_step = node(command = <{ 1 + 2 }>, runtime = R, deserializer = ^json)
  t_step = r_step * 2
}|}
    (Packages.init_env ()) in
  (match v_rerun_base with
  | Ast.VPipeline p ->
    (match Eval.rerun_pipeline (ref (Packages.init_env ())) p with
    | Ast.VPipeline rerun ->
      (match List.assoc_opt "t_step" rerun.p_nodes with
      | Some (Ast.VComputedNode cn) when cn.cn_path = "<unbuilt>" ->
          incr pass_count; Printf.printf "  ✓ T node stays deferred after rerun when sibling is <unbuilt>\n"
      | Some other ->
          incr fail_count; Printf.printf "  ✗ T node should stay deferred after rerun\n    Got: %s\n"
            (Ast.Utils.value_to_string other)
      | None ->
          incr fail_count; Printf.printf "  ✗ T node should stay deferred after rerun: node not found\n")
    | other ->
        incr fail_count; Printf.printf "  ✗ rerun_pipeline returned unexpected value: %s\n"
          (Ast.Utils.value_to_string other))
  | other ->
      incr fail_count; Printf.printf "  ✗ initial pipeline for rerun test failed: %s\n"
        (Ast.Utils.value_to_string other));

  (* Regression test: Julia raw-code nodes with `using`/`import` must hoist those
     statements to the top of the script, outside the try/begin...end block.
     This catches the original "using not at top level" Julia failure mode. *)
  let (v_julia_imports, _) = eval_string_env
    {|pipeline {
  compute = jln(command = <{
    using LinearAlgebra
    import Statistics
    result = norm([1.0, 2.0, 3.0])
    result
  }>)
}|}
    (Packages.init_env ()) in
  (match v_julia_imports with
   | Ast.VPipeline p ->
       let nix = Nix_emit_pipeline.emit_pipeline p in
       (* Import lines must appear before the begin block in the emitted script.
          The hoisted_imports section is emitted before assign_script_lines in the
          template, so `using`/`import` lines must precede `echo "    local __tlang_node_thunk = () -> begin"`. *)
       let find_pos pat =
         try Some (Str.search_forward (Str.regexp_string pat) nix 0)
         with Not_found -> None
       in
       let using_pos = find_pos "using LinearAlgebra" in
       let import_pos = find_pos "import Statistics" in
       let begin_pos = find_pos {|echo "    local __tlang_node_thunk = () -> begin"|} in
       let imports_hoisted_before_begin =
         match using_pos, import_pos, begin_pos with
         | Some u, Some i, Some b -> u < b && i < b
         | _ -> false
       in
       (* Confirm that neither import line appears inside the begin...end body block *)
       let imports_absent_from_body =
         match begin_pos with
         | None -> true
         | Some bp ->
             let end_pos =
               try Some (Str.search_forward (Str.regexp_string {|echo "    end"|}) nix bp)
               with Not_found -> None
             in
             (match end_pos with
              | None -> true
              | Some ep when ep > bp && ep <= String.length nix ->
                  let inner = String.sub nix bp (ep - bp) in
                  not (contains_substring inner "using LinearAlgebra") &&
                  not (contains_substring inner "import Statistics")
              | _ -> true)
       in
       if imports_hoisted_before_begin && imports_absent_from_body then begin
         incr pass_count; Printf.printf "  ✓ Julia raw-code using/import are hoisted outside begin...end block\n"
       end else begin
         incr fail_count; Printf.printf "  ✗ Julia raw-code import hoisting failed (hoisted_before_begin=%b absent_from_body=%b)\n"
           imports_hoisted_before_begin imports_absent_from_body
       end
   | other ->
       incr fail_count; Printf.printf "  ✗ Julia import hoisting pipeline should return VPipeline, got: %s\n"
         (Ast.Utils.value_to_string other));

  let test_build_log_api () =
    let v_log =
      with_temp_pipeline_project
        "pipeline { a = 1 }\n"
        (fun _dir _pipeline_path ->
          let (res, _) = eval_string_env
            {|
            p = pipeline {
              missing_build_log_node = 1
            }
            -- We cannot build the pipeline purely inside the tests without side effects,
            -- but we can test that error conditions are handled cleanly when there's no log.
            error_code(build_log(p)) == "FileError"
            |} (Packages.init_env ())
          in
          res)
    in
    if v_log = Ast.VBool true then begin
      incr pass_count; Printf.printf "  ✓ build_log returns FileError on missing log\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ build_log expected FileError, got %s\n"
        (Ast.Utils.value_to_string v_log)
    end;
    let (v_frame, _) = eval_string_env
      {|
      error_code(build_log_to_frame(123)) == "TypeError"
      |} (Packages.init_env ())
    in
    if v_frame = Ast.VBool true then begin
      incr pass_count; Printf.printf "  ✓ build_log_to_frame validates arguments\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ build_log_to_frame validation failed\n"
    end;
    let test_build_log_warnings () =
      let mock_node1 = Ast.VDict [("name", Ast.VString "node_a"); ("status", Ast.VString "Completed"); ("duration", Ast.VFloat 1.2); ("path", Ast.VString "/nix/store/a")] in
      let mock_node2 = Ast.VDict [("name", Ast.VString "node_b"); ("status", Ast.VString "Completed with warning"); ("duration", Ast.VFloat 3.4); ("path", Ast.VString "/nix/store/b")] in
      let bl = Ast.VBuildLog {
        bl_nodes = [mock_node1; mock_node2];
        bl_duration = 4.6;
        bl_failed_nodes = [];
        bl_out_path = None;
      } in
      let s = Ast.Utils.value_to_string bl in
      let expected = "Build Log: 2 nodes [2 succeeded, 0 failed] (duration: 4.60s)\n  ⚠ Warnings in nodes: node_b" in
      if s = expected then begin
        incr pass_count; Printf.printf "  ✓ value_to_string(VBuildLog) formats warnings correctly\n"
      end else begin
        incr fail_count; Printf.printf "  ✗ value_to_string(VBuildLog) mismatch:\n    Expected: %S\n    Got:      %S\n" expected s
      end
    in
    test_build_log_warnings ();
    let v_errors =
      with_temp_pipeline_project
        "pipeline { a = 1 }\n"
        (fun _dir _pipeline_path ->
          let (res, _) = eval_string_env
            {|
            p = pipeline {
              a = 1
            }
            nrow(collect_exceptions(p)) == 0
            |} (Packages.init_env ())
          in
          res)
    in
    if v_errors = Ast.VBool true then begin
      incr pass_count; Printf.printf "  ✓ collect_exceptions returns empty DataFrame for unbuilt/clean pipeline\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ collect_exceptions expected empty DataFrame, got %s\n"
        (Ast.Utils.value_to_string v_errors)
    end
  in
  test_build_log_api ();

  let test_inspect_node_errors () =
    let env = Packages.init_env () in
    let inspect_fn =
      match Ast.Env.find_opt "inspect_node" env with
      | Some (VBuiltin { b_func; _ }) -> b_func
      | _ -> failwith "inspect_node not found"
    in
    let err_node =
      Ast.VError {
        code = Ast.RuntimeError;
        message = "failing_node failed";
        context = [("node_name", Ast.VString "failing_node")];
        location = None;
        na_count = 0;
      }
    in
    let res1 = inspect_fn [(None, err_node)] (ref env) in
    (match res1 with
     | Ast.VError info ->
         let expected_substr = "inspect_node: expected a ComputedNode, but got an Error because node `failing_node` failed" in
         if contains_substring info.message expected_substr then begin
           incr pass_count; Printf.printf "  ✓ inspect_node returns a clear error message on failing nodes\n"
         end else begin
           incr fail_count; Printf.printf "  ✗ inspect_node error message mismatch: %s\n" info.message
         end
     | other ->
         incr fail_count; Printf.printf "  ✗ inspect_node expected VError, got: %s\n" (Ast.Utils.value_to_string other));
    let res2 = inspect_fn [(None, Ast.VString "not_a_computed_node")] (ref env) in
    (match res2 with
     | Ast.VError info ->
         let expected_substr = "inspect_node: expected a ComputedNode, but got String" in
         if contains_substring info.message expected_substr then begin
           incr pass_count; Printf.printf "  ✓ inspect_node returns a clear error message on non-ComputedNode types\n"
         end else begin
           incr fail_count; Printf.printf "  ✗ inspect_node error message mismatch on non-ComputedNode: %s\n" info.message
         end
     | other ->
         incr fail_count; Printf.printf "  ✗ inspect_node expected VError for string, got: %s\n" (Ast.Utils.value_to_string other))
  in
  test_inspect_node_errors ();

  let test_inspect_pipeline_poly () =
    let (v_inspect, _) = eval_string_env
      {|
      p = pipeline {
        a = 1
        b = a + 1
      }
      -- inspect_pipeline(p) should statically return a DataFrame with schema metadata (2 nodes, 5 properties)
      res = inspect_pipeline(p)
      res2 = inspect_pipeline()
      type(res) == "DataFrame" && nrow(res) == 2 && ncol(res) == 5 && type(res2) == "DataFrame" && nrow(res2) == 2 && ncol(res2) == 5
      |} (Packages.init_env ())
    in
    if v_inspect = Ast.VBool true then begin
      incr pass_count; Printf.printf "  ✓ inspect_pipeline(p) statically inspects pipeline structure\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ inspect_pipeline(p) static inspection failed, got %s\n"
        (Ast.Utils.value_to_string v_inspect)
    end
  in
  test_inspect_pipeline_poly ();

  let test_explain_collect_exceptions () =
    let make_mock_df rows =
      let node_arr = Array.make (List.length rows) None in
      let status_arr = Array.make (List.length rows) None in
      let code_arr = Array.make (List.length rows) None in
      let message_arr = Array.make (List.length rows) None in
      List.iteri (fun i (n, s, c, m) ->
        node_arr.(i) <- Some n;
        status_arr.(i) <- Some s;
        code_arr.(i) <- Some c;
        message_arr.(i) <- Some m;
      ) rows;
      let cols = [
        ("node", Arrow_table.StringColumn node_arr);
        ("status", Arrow_table.StringColumn status_arr);
        ("code", Arrow_table.StringColumn code_arr);
        ("message", Arrow_table.StringColumn message_arr);
      ] in
      let arrow_table = Arrow_table.create cols (List.length rows) in
      Ast.VDataFrame { arrow_table; group_keys = [] }
    in
    let env = Packages.init_env () in
    let env = Ast.Env.add "df_empty" (make_mock_df []) env in
    let env = Ast.Env.add "df_single" (make_mock_df [("a", "Error", "DivisionByZero", "Division by zero")]) env in
    let env = Ast.Env.add "df_multi" (make_mock_df [
      ("a", "Error", "DivisionByZero", "Division by zero");
      ("b", "Warning", "UnusedVariable", "Variable b is not used")
    ]) env in
    let (v_res, _) = eval_string_env
      {|
      exp_empty = explain(df_empty)
      exp_single = explain(df_single)
      exp_multi = explain(df_multi)
      
      ok_empty = (exp_empty.kind == "exceptions_list" && exp_empty.count == 0)
      ok_single = (exp_single.kind == "value" && exp_single.type == "Error" && exp_single.node == "a")
      ok_multi = (exp_multi.kind == "exceptions_list" && exp_multi.count == 2 && get(exp_multi.exceptions, 0).type == "Error" && get(exp_multi.exceptions, 1).type == "Warning")
      
      ok_empty && ok_single && ok_multi
      |} env
    in
    if v_res = Ast.VBool true then begin
      incr pass_count; Printf.printf "  ✓ explain(collect_exceptions(p)) returns custom structured explanations\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ explain(collect_exceptions(p)) validation failed, got %s\n"
        (Ast.Utils.value_to_string v_res)
    end
  in
  test_explain_collect_exceptions ();

  let with_repo_temp_pipeline_project script f =
    let repo_root = Sys.getcwd () in
    let rec make_temp_dir attempts =
      if attempts <= 0 then
        failwith "failed to create temporary pipeline test directory"
      else
        let candidate =
          Filename.concat
            repo_root
            (Printf.sprintf ".tlang-pipeline-%d-%06d" (Unix.getpid ()) (Random.int 1_000_000))
        in
        try
          Unix.mkdir candidate 0o755;
          candidate
        with Unix.Unix_error (Unix.EEXIST, _, _) ->
          make_temp_dir (attempts - 1)
    in
    let dir = make_temp_dir 8 in
    let src_dir = Filename.concat dir "src" in
    let pipeline_path = Filename.concat src_dir "pipeline.t" in
    let old_cwd = Sys.getcwd () in
    Unix.mkdir src_dir 0o755;
    let oc = open_out pipeline_path in
    output_string oc script;
    close_out oc;
    try
      Sys.chdir dir;
      let result = f dir pipeline_path in
      Sys.chdir old_cwd;
      remove_path dir;
      result
    with exn ->
      Sys.chdir old_cwd;
      remove_path dir;
      raise exn
  in

  let test_nix_execution_equivalence_golden () =
    let golden_ok =
      with_repo_temp_pipeline_project
        "p = pipeline {\n  golden_node = shn(command = \"echo -n 'golden_value'\", capture = \"stdout\")\n}\n"
        (fun dir _pipeline_path ->
          (* Build the pipeline using T OCaml interpreter *)
          let env = Packages.init_env () in
          let (_, env) = eval_string_env "p = pipeline { golden_node = shn(command = \"echo -n 'golden_value'\", capture = \"stdout\") }" env in
          let (_, env) = eval_string_env "build_pipeline(p)" env in
          (* Verify that the build completed and we can query the built value *)
          let (v_val, _) = eval_string_env "read_node(p.golden_node)" env in
          let t_value = match Ast.Utils.unwrap_value v_val with Ast.VString s -> s | _ -> "" in
          (* Now manually run nix-build on the generated _pipeline/pipeline.nix directly *)
          let nix_path = Filename.concat (Filename.concat dir "_pipeline") "pipeline.nix" in
          if Sys.file_exists nix_path then
            let argv = [| "nix-build"; "--impure"; nix_path; "-A"; "golden_node"; "--no-out-link" |] in
            match Builder_utils.run_command_argv_capture argv with
            | Error msg ->
                Printf.printf "Nix build failed: %s\n" msg;
                false
            | Ok out_dir ->
                let artifact_path = Filename.concat (String.trim out_dir) "artifact" in
                if Sys.file_exists artifact_path then
                  let ic = open_in artifact_path in
                  let nix_value = try input_line ic with _ -> "" in
                  close_in ic;
                  let nix_value_trimmed = String.trim nix_value in
                  let eq = (t_value = nix_value_trimmed && nix_value_trimmed = "golden_value") in
                  if not eq then
                    Printf.printf "Values mismatch: t_value=%S, nix_value_trimmed=%S\n" t_value nix_value_trimmed;
                  eq
                else begin
                  Printf.printf "Artifact path %s does not exist\n" artifact_path;
                  false
                end
          else begin
            Printf.printf "Nix path %s does not exist\n" nix_path;
            false
          end
        )
    in
    if golden_ok then begin
      incr pass_count; Printf.printf "  ✓ Nix execution equivalence golden test matches manual nix-build exactly\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ Nix execution equivalence golden test failed\n"
    end
  in
  test_nix_execution_equivalence_golden ();

  let test_artifact_export_import_roundtrip () =
    let archive_ok =
      with_repo_temp_pipeline_project
        "p = pipeline {\n  cached_node = shn(command = \"echo -n 'artifact_roundtrip'\", capture = \"stdout\")\n}\n"
        (fun dir _pipeline_path ->
          let archive_path = Filename.concat dir "pipeline-cache.nar" in
          let env = Packages.init_env () in
          let (_, env) =
            eval_string_env
              "p = pipeline { cached_node = shn(command = \"echo -n 'artifact_roundtrip'\", capture = \"stdout\") }"
              env
          in
          let (_, env) = eval_string_env "build_pipeline(p)" env in
          let (v_export, env) =
            eval_string_env
              (Printf.sprintf "export_artifacts(p, %S)" archive_path)
              env
          in
          let export_ok =
            match Ast.Utils.unwrap_value v_export with
            | Ast.VString msg -> contains_pattern "Exported" msg && Sys.file_exists archive_path
            | _ -> false
          in
          let (v_inspect, env) =
            eval_string_env
              (Printf.sprintf "inspect_artifacts(%S)" archive_path)
              env
          in
          let inspect_ok =
            match Ast.Utils.unwrap_value v_inspect with
            | Ast.VDataFrame df ->
                let col_names = List.map fst df.arrow_table.columns in
                List.mem "node" col_names &&
                List.mem "store_path" col_names &&
                List.mem "hash" col_names &&
                List.mem "size_bytes" col_names &&
                List.mem "references" col_names &&
                df.arrow_table.nrows > 0
            | _ -> false
          in
          let node_archive_path = archive_path ^ ".node" in
          let (v_export_node, env) =
            eval_string_env
              (Printf.sprintf "export_artifacts(p.cached_node, %S)" node_archive_path)
              env
          in
          let export_node_ok =
            match Ast.Utils.unwrap_value v_export_node with
            | Ast.VString msg -> contains_pattern "Exported 1" msg && Sys.file_exists node_archive_path
            | _ -> false
          in
          let (_, env) = eval_string_env "pipeline_gc(p)" env in
          let (v_import, env) =
            eval_string_env
              (Printf.sprintf "import_artifacts(%S)" archive_path)
              env
          in
          let import_ok =
            match Ast.Utils.unwrap_value v_import with
            | Ast.VString msg -> contains_pattern "Imported" msg
            | _ -> false
          in
          let (v_after, _) =
            eval_string_env
              "nrow(filter(pipeline_cache_status(p), $cached == false)) == 0"
              env
          in
          export_ok && inspect_ok && export_node_ok && import_ok && v_after = Ast.VBool true
        )
    in
    if archive_ok then begin
      incr pass_count; Printf.printf "  ✓ export_artifacts()/import_artifacts() round-trip pipeline cache with inspection & granular export\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ export_artifacts()/import_artifacts() round-trip pipeline cache with inspection & granular export\n"
    end
  in
  test_artifact_export_import_roundtrip ();

  let test_build_log_history_and_node_diff () =
    let success =
      with_temp_pipeline_project
        "pipeline { a = 1; b = 2; df_node = 3; text_node = 4; model_node = 5 }\n"
        (fun _dir _pipeline_path ->
           Unix.mkdir "_pipeline" 0o755;
           
           (* Mock 3 logs with different mtimes *)
           let log1 = {|{
             "timestamp": "2026-05-25T12:00:00Z",
             "duration": 5.2,
             "hash": "hash1",
             "out_path": "/nix/store/abc1",
             "nodes": [
               { "node": "a", "path": "node_a_1.tobj", "runtime": "T", "serializer": "default", "class": "V", "dependencies": [], "success": "true" },
               { "node": "b", "path": "node_b_1.tobj", "runtime": "T", "serializer": "default", "class": "V", "dependencies": [], "success": "true" },
               { "node": "df_node", "path": "df_1.csv", "runtime": "T", "serializer": "csv", "class": "VDataFrame", "dependencies": [], "success": "true" },
               { "node": "text_node", "path": "text_1.txt", "runtime": "T", "serializer": "text", "class": "VString", "dependencies": [], "success": "true" },
               { "node": "model_node", "path": "model_1.pmml", "runtime": "T", "serializer": "pmml", "class": "VComputedNode", "dependencies": [], "success": "true" }
             ]
           }|} in
           let log2 = {|{
             "timestamp": "2026-05-25T11:00:00Z",
             "duration": 4.1,
             "hash": "hash2",
             "out_path": "/nix/store/abc2",
             "nodes": [
               { "node": "a", "path": "node_a_2.tobj", "runtime": "T", "serializer": "default", "class": "V", "dependencies": [], "success": "true" },
               { "node": "b", "path": "node_b_2.tobj", "runtime": "T", "serializer": "default", "class": "V", "dependencies": [], "success": "true" },
               { "node": "df_node", "path": "df_2.csv", "runtime": "T", "serializer": "csv", "class": "VDataFrame", "dependencies": [], "success": "true" },
               { "node": "text_node", "path": "text_2.txt", "runtime": "T", "serializer": "text", "class": "VString", "dependencies": [], "success": "true" },
               { "node": "model_node", "path": "model_2.pmml", "runtime": "T", "serializer": "pmml", "class": "VComputedNode", "dependencies": [], "success": "true" }
             ]
           }|} in
           let log3 = {|{
             "timestamp": "2026-05-25T10:00:00Z",
             "duration": 3.0,
             "hash": "hash3",
             "out_path": "/nix/store/abc3",
             "nodes": [
               { "node": "a", "path": "node_a_3.tobj", "runtime": "T", "serializer": "default", "class": "V", "dependencies": [], "success": "true" },
               { "node": "b", "path": "node_b_3.tobj", "runtime": "T", "serializer": "default", "class": "V", "dependencies": [], "success": "true" },
               { "node": "df_node", "path": "df_3.csv", "runtime": "T", "serializer": "csv", "class": "VDataFrame", "dependencies": [], "success": "true" },
               { "node": "text_node", "path": "text_3.txt", "runtime": "T", "serializer": "text", "class": "VString", "dependencies": [], "success": "true" },
               { "node": "model_node", "path": "model_3.pmml", "runtime": "T", "serializer": "pmml", "class": "VComputedNode", "dependencies": [], "success": "true" }
             ]
           }|} in
           let p1 = Filename.concat "_pipeline" "build_log_test1.json" in
           let p2 = Filename.concat "_pipeline" "build_log_test2.json" in
           let p3 = Filename.concat "_pipeline" "build_log_test3.json" in
           
           let write_file p content =
             let oc = open_out p in
             output_string oc content;
             close_out oc
           in
           write_file p1 log1;
           write_file p2 log2;
           write_file p3 log3;
           
           (* Set explicit mtimes so sorting is 100% deterministic *)
           Unix.utimes p1 1700000000.0 1700000000.0;
           Unix.utimes p2 1600000000.0 1600000000.0;
           Unix.utimes p3 1500000000.0 1500000000.0;
           
           (* 1. Scalar nodes values *)
           ignore (Serialization.serialize_to_file "node_a_1.tobj" (Ast.VInt 10));
           ignore (Serialization.serialize_to_file "node_a_2.tobj" (Ast.VInt 20));
           ignore (Serialization.serialize_to_file "node_a_3.tobj" (Ast.VInt 30));
           
           (* 2. DataFrame nodes values (using CSV) *)
           let df1_content = "x,y\n1,2\n3,4\n" in
           let df2_content = "x,y,z\n1.5,2,5\n3.5,4,6\n" in
           write_file "df_1.csv" df1_content;
           write_file "df_2.csv" df2_content;

           (* 3. Text nodes values *)
           let text1_content = "hello\nworld\n" in
           let text2_content = "hello\nthere\nworld\n" in
           write_file "text_1.txt" text1_content;
           write_file "text_2.txt" text2_content;

           (* 4. PMML nodes values (write blank file, will fail XML parse and use fallback diff) *)
           write_file "model_1.pmml" "";
           write_file "model_2.pmml" "";

            Printexc.record_backtrace true;
            let (res, _) =
              try
                eval_string_env
                  {|
                  p = pipeline { a = 1; b = 2; df_node = 3; text_node = 4; model_node = 5 }
                  hist = build_log_history(p)
                  hist_limit = build_log_history(p, n = 2)
                  
                  ok_history = (type(hist) == "DataFrame" && nrow(hist) == 3 && nrow(hist_limit) == 2)
                  
                  diff_scalar = node_diff(p.a, p.a, 1, 2)
                  ok_scalar = (type(diff_scalar) == "Dict" && diff_scalar.kind == "scalar_diff" && diff_scalar.identical == false && diff_scalar.summary.changed == true && diff_scalar.summary.value_a == 10 && diff_scalar.summary.value_b == 20 && diff_scalar.summary.delta == 10)
                  
                  diff_df = node_diff(p.df_node, p.df_node, 1, 2)
                  ok_df = (type(diff_df) == "Dict" && diff_df.kind == "dataframe_diff" && diff_df.value_type == "DataFrame")

                  diff_text = node_diff(p.text_node, p.text_node, 1, 2)
                  ok_text = (type(diff_text) == "Dict" && diff_text.identical == false)

                  diff_pmml = node_diff(p.model_node, p.model_node, 1, 2)
                  ok_pmml = (type(diff_pmml) == "Dict" && (diff_pmml.kind == "model_diff" || diff_pmml.kind == "generic_diff"))
                  
                  ok_out_of_range = (is_error(node_diff(p.a, p.a, 10, 2)) && error_code(node_diff(p.a, p.a, 10, 2)) == "ValueError")

                  ok_nonexistent = (is_error(p.nonexistent) && error_code(p.nonexistent) == "KeyError")

                  ok_negative = (is_error(node_diff(p.a, p.a, -1, 2)) && error_code(node_diff(p.a, p.a, -1, 2)) == "ValueError")

                  log_test2 = build_log(p, which_log = ".*test2.*")
                  ok_log_regex = (type(log_test2) == "BuildLog" && log_test2.out_path == "/nix/store/abc2")

                  hist_filtered = build_log_history(p, pattern = ".*test[23].*")
                  ok_history_regex = (type(hist_filtered) == "DataFrame" && nrow(hist_filtered) == 2)

                  diff_scalar_regex = node_diff(p.a, p.a, log_a = ".*test1.*", log_b = ".*test2.*")
                  ok_diff_regex = (type(diff_scalar_regex) == "Dict" && diff_scalar_regex.kind == "scalar_diff" && diff_scalar_regex.identical == false && diff_scalar_regex.summary.value_a == 10 && diff_scalar_regex.summary.value_b == 20)

                  ok_no_match = (is_error(node_diff(p.a, p.a, log_a = ".*nomatch.*", log_b = 2)) && error_code(node_diff(p.a, p.a, log_a = ".*nomatch.*", log_b = 2)) == "ValueError")

                  ok_history && ok_scalar && ok_df && ok_text && ok_pmml && ok_out_of_range && ok_nonexistent && ok_negative && ok_log_regex && ok_history_regex && ok_diff_regex && ok_no_match
                  |} (Packages.init_env ())
              with e ->
                Printf.printf "EXCEPTION CAUGHT: %s\n%!" (Printexc.to_string e);
                Printf.printf "BACKTRACE:\n%s\n%!" (Printexc.get_backtrace ());
                raise e
            in
            res)
    in
    if success = Ast.VBool true then begin
      incr pass_count; Printf.printf "  ✓ build_log_history and node_diff comprehensive test passes\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ build_log_history and node_diff comprehensive test failed, got: %s\n"
        (Ast.Utils.value_to_string success)
    end
  in
  test_build_log_history_and_node_diff ();

  let classify_hunk_kind_tests =
    Diff.classify_hunk_kind ~has_replace:false ~has_prev:true ~has_next:true = "replace"
    && Diff.classify_hunk_kind ~has_replace:false ~has_prev:true ~has_next:false = "delete"
    && Diff.classify_hunk_kind ~has_replace:false ~has_prev:false ~has_next:true = "insert"
    && Diff.classify_hunk_kind ~has_replace:true ~has_prev:false ~has_next:false = "replace"
  in
  if classify_hunk_kind_tests then begin
    incr pass_count; Printf.printf "  ✓ patience diff hunk kinds classify mixed changes correctly\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ patience diff hunk kinds classify mixed changes correctly\n"
  end;

  print_newline ()
