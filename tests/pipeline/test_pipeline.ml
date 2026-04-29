
let run_tests pass_count fail_count _eval_string eval_string_env test =
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
  let verbose_args_ok =
    Builder_internal.nix_verbosity_args 0 = ["--quiet"]
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
        let (new_binding_check, _) = eval_string_env "other == 2 && p.b == 2" env in
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
    {|Error(StructuralError: "Pipeline has a dependency cycle involving node `a`.")|};
  test "pipeline with error in node"
    "pipeline {\n  a = 1 / 0\n  b = a + 1\n}"
    "Pipeline(2 nodes: [a, b])\nErrors:\n  - `a` failed: Pipeline node `a` failed: Division by zero.\n  - `b` failed: Pipeline node `b` failed: Pipeline node `a` failed: Division by zero.";
  
  test "explain shows runtime for T node error"
    "p = pipeline { a = 1 / 0 }; info = explain(p.a); info.runtime"
    "\"T\"";

  test "explain shows runtime for upstream T error"
    "p = pipeline { a = 1 / 0; b = a + 1 }; info = explain(p.b); info.runtime"
    "\"T\"";

  (try Unix.mkdir "_pipeline" 0o755 with _ -> ());
  let ensure_temp_dir name =
    let dir = Filename.concat (Filename.get_temp_dir_name ()) name in
    if not (Sys.file_exists dir) then
      try Unix.mkdir dir 0o755 with
      | Unix.Unix_error (Unix.EEXIST, _, _) -> ();
    dir
  in
  let error_node_dir = ensure_temp_dir "tlang-error-node" in
  let plot_json_dir = ensure_temp_dir "tlang-plot-fallback" in
  Fun.protect
    ~finally:(fun () ->
      remove_path error_node_dir;
      remove_path plot_json_dir)
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
      let mock_log = {|{
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
      ignore (Serialization.write_json plot_json_path
        (Ast.VDict [
          ("class", Ast.VString "matplotlib");
          ("backend", Ast.VString "Python");
          ("title", Ast.VString "Fallback plot");
          ("mapping", Ast.VDict []);
          ("labels", Ast.VDict [("x", Ast.VString "x"); ("y", Ast.VString "y")]);
          ("layers", Ast.VList [(None, Ast.VString "Line2D")]);
        ]));
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

      test "read_node propagates R runtime on error"
        "explain(read_node(\"r_fail\", which_log=\"ocaml_mock\")).runtime"
        "\"R\"";

      test "read_node propagates Python runtime on error"
        "explain(read_node(\"py_fail\", which_log=\"ocaml_mock\")).runtime"
        "\"Python\"";
      test "read_node (mocked) reads compatible artifact"
        "read_node(\"compatible_node\", which_log=\"legacy_version\") .== [1, 2, 3]"
        "[true, true, true]";
      test "read_node missing key (mocked)"
        "error_code(read_node(\"missing\", which_log=\"ocaml_mock\")) == \"KeyError\""
        "true";
      test "read_node error exposes error_code field"
        "read_node(\"error_node\", which_log=\"ocaml_mock\").error_code"
        {|"RuntimeError"|};
      test "read_node error exposes error_message field"
        "read_node(\"error_node\", which_log=\"ocaml_mock\").error_message"
        (Ast.Utils.value_to_string (Ast.VString mocked_error_message));
      test "read_node error exposes context dict"
        "read_node(\"error_node\", which_log=\"ocaml_mock\").context.node_status"
        {|"errored"|};

      test "read_node falls back to artifact deserializer when plot viz sidecar is absent"
        "read_node(\"plot_json_node\", which_log=\"legacy_version\").title"
        {|"Fallback plot"|};
      test "plot fallback fixture does not create a viz sidecar"
        (Printf.sprintf {|file_exists("%s")|} plot_json_viz)
        "false";

      test "read_node rejects older serialized node versions"
        "read_node(\"legacy_node\", which_log=\"legacy_version\")"
        legacy_node_error);

  print_newline ();

  Printf.printf "Phase 3 — Pipeline Diagnostics:\n";
  test "read_node(p, name) exposes warning list"
    {|p_diag = pipeline {
  data = dataframe([[x: 1], [x: NA], [x: 3]])
  filtered = filter(data, $x > 1)
  count = nrow(filtered)
}; length(read_node(p_diag, "filtered").warnings)|}
    "1";
  test "downstream nodes inherit upstream warnings"
    {|p_diag = pipeline {
  data = dataframe([[x: 1], [x: NA], [x: 3]])
  filtered = filter(data, $x > 1)
  count = nrow(filtered)
}; read_node(p_diag, "count").warnings |> map(\(w) w.source.kind)|}
    {|["Upstream"]|};
  test "downstream warning source points at origin node"
    {|p_diag = pipeline {
  data = dataframe([[x: 1], [x: NA], [x: 3]])
  filtered = filter(data, $x > 1)
  count = nrow(filtered)
}; read_node(p_diag, "count").warnings |> map(\(w) w.source.node)|}
    {|["filtered"]|};
  test "read_pipeline summarizes warning origins only once"
    {|p_diag = pipeline {
  data = dataframe([[x: 1], [x: NA], [x: 3]])
  filtered = filter(data, $x > 1)
  count = nrow(filtered)
}; read_pipeline(p_diag).diagnostics.summary|}
    "\"1 node(s) with warnings, 0 suppressed, 0 error(s), 0 recovered\"";
  test "read_pipeline tracks error nodes"
    {|p_err = pipeline {
  bad = 1 / 0
  downstream = bad + 1
}; read_pipeline(p_err).diagnostics.summary|}
    "\"0 node(s) with warnings, 0 suppressed, 2 error(s), 0 recovered\"";
  test "read_node(p, name) exposes structured node errors"
    {|p_err = pipeline {
  bad = 1 / 0
  downstream = bad + 1
}; read_node(p_err, "bad").error.kind|}
    "\"DivisionByZero\"";
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
       incr pass_count; Printf.printf "  ✓ py() stores env_vars on the node\n"
   | other ->
       incr fail_count; Printf.printf "  ✗ py() env_vars parsing failed: %s\n"
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
  step = py(command = <{ data + 1 }>, env_vars = [MODE: "fast"], deserializer = "json")
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
  model = rn(command = <{ 1 + 1 }>, env_vars = [MODEL_MODE: "train", RETRIES: 2], deserializer = "json")
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
  report_r = rn(command = <{ source }>, serializer = "json", deserializer = "json")
  report_py = py(command = <{ source }>, serializer = "arrow", deserializer = "arrow")
}|}
    (Packages.init_env ()) in
  (match v_serializer_pipeline with
   | Ast.VPipeline p ->
        let nix = Nix_emit_pipeline.emit_pipeline p in
        let has_r_json_helpers =
         contains_substring nix "r_write_json <- function" &&
         contains_substring nix "r_read_json <- function" &&
         contains_substring nix "source <- r_read_json(" &&
         contains_substring nix "r_write_json(report_r,"
       in
        let has_py_arrow_helpers =
          contains_substring nix "def py_write_arrow(df, path):" &&
          contains_substring nix "def py_read_arrow(path):" &&
          contains_substring nix "source = py_read_arrow(" &&
          contains_substring nix "py_write_arrow(report_py,"
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
  plot_py = py(command = <{
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots()
    ax.plot([1, 2], [3, 4])
    fig
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
         contains_substring nix "r_save_viz_metadata(plot_r, file.path(Sys.getenv('out'), 'viz'))"
       in
        let has_py_plot_helpers =
          contains_substring nix "def py_extract_plot_metadata(obj):" &&
          contains_substring nix "from plotnine.ggplot import ggplot as PlotnineGGPlot" &&
          contains_substring nix "\"class\": \"plotnine\"" &&
          contains_substring nix "\"backend\": \"Python\"" &&
          contains_substring nix "py_visual_class(plot_py)" &&
          contains_substring nix "py_save_viz_metadata(plot_py, os.path.join(os.environ['out'], 'viz'))"
        in
       if has_r_plot_helpers && has_py_plot_helpers then begin
         incr pass_count; Printf.printf "  ✓ pipeline emits plot metadata helpers for R and Python nodes\n"
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
  r_step = node(command = <{ 1 + 2 }>, runtime = R, deserializer = "json")
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
  if contains_substring name_err_str "Name `nonexistent_func_xyzzy` is not defined." then begin
    incr pass_count; Printf.printf "  ✓ undefined function in T node raises NameError (not silently deferred)\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ undefined function in T node should raise NameError\n    Got: %s\n" name_err_str
  end;

  (* Test: rerun_pipeline correctly keeps a T node deferred when its sibling is <unbuilt> *)
  let (v_rerun_base, _) = eval_string_env
    {|pipeline {
  r_step = node(command = <{ 1 + 2 }>, runtime = R, deserializer = "json")
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

  print_newline ()
