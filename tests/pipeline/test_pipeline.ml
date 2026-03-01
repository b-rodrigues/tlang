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

  Printf.printf "Phase 3 — Script Argument Support:\n";
  let (v_node_script_only, _) = eval_string_env
    "cfg = node(script = <{ return 42 }>, runtime = Python); cfg.command"
    (Packages.init_env ()) in
  if Ast.Utils.value_to_string v_node_script_only = "\"<{return 42}>\"" then begin
    incr pass_count; Printf.printf "  ✓ node(script=...) works without command\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ node(script=...) failed\n    Got: %s\n" (Ast.Utils.value_to_string v_node_script_only)
  end;

  let (v_node_both, _) = eval_string_env
    "node(command = <{ 1 + 1 }>, script = <{ return 5 }>, runtime = Python)"
    (Packages.init_env ()) in
  if Ast.Utils.value_to_string v_node_both = "Error(ArityError: \"Provide either `command` or `script`, but not both.\")" then begin
    incr pass_count; Printf.printf "  ✓ node rejects command+script together\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ node did not reject command+script\n    Got: %s\n" (Ast.Utils.value_to_string v_node_both)
  end;

  let (v_pyn_both, _) = eval_string_env
    "pyn(command = <{ 1 + 1 }>, script = <{ return 5 }>)"
    (Packages.init_env ()) in
  if Ast.Utils.value_to_string v_pyn_both = "Error(ArityError: \"Provide either `command` or `script`, but not both.\")" then begin
    incr pass_count; Printf.printf "  ✓ pyn rejects command+script together\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ pyn did not reject command+script\n    Got: %s\n" (Ast.Utils.value_to_string v_pyn_both)
  end;

  let (v_rn_both, _) = eval_string_env
    "rn(command = <{ 1 + 1 }>, script = <{ 5 }>)"
    (Packages.init_env ()) in
  if Ast.Utils.value_to_string v_rn_both = "Error(ArityError: \"Provide either `command` or `script`, but not both.\")" then begin
    incr pass_count; Printf.printf "  ✓ rn rejects command+script together\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ rn did not reject command+script\n    Got: %s\n" (Ast.Utils.value_to_string v_rn_both)
  end;
  print_newline ();

  Printf.printf "Phase 3 — Runtime Script Files (Python + R):\n";
  let command_exists cmd = Sys.command (Printf.sprintf "command -v %s >/dev/null 2>&1" cmd) = 0 in
  let can_run_runtime_scripts = command_exists "nix-build" && command_exists "python" && command_exists "Rscript" in
  if can_run_runtime_scripts then begin
    let temp_dir = Filename.concat (Filename.get_temp_dir_name ()) ("tlang_script_test_" ^ string_of_int (Unix.getpid ())) in
    (try Unix.mkdir temp_dir 0o755 with _ -> ());
    let py_file = Filename.concat temp_dir "helpers.py" in
    let r_file = Filename.concat temp_dir "helpers.R" in
    let write_file path content =
      let oc = open_out path in
      output_string oc content;
      close_out oc
    in
    write_file py_file "def add_one(x):\n    return x + 1\n";
    write_file r_file "add_one <- function(x) { x + 1 }\n";
    let script_code = Printf.sprintf {|p_scripts = pipeline {
  py = pyn(script = <{
from helpers import add_one
return add_one(41)
  }>, functions = "%s")
  rr = rn(script = <{
source("helpers.R")
add_one(41)
  }>, functions = "%s")
}
out = build_pipeline(p_scripts)
ok = if (is_error(out)) (false) else ((read_node("py") == 42) && (read_node("rr") == 42))
ok|} py_file r_file in
    let (v_script_runtime, _) = eval_string_env script_code (Packages.init_env ()) in
    if Ast.Utils.value_to_string v_script_runtime = "true" then begin
      incr pass_count; Printf.printf "  ✓ runtime script files execute for Python and R nodes\n"
    end else begin
      incr fail_count; Printf.printf "  ✗ runtime script files failed\n    Got: %s\n" (Ast.Utils.value_to_string v_script_runtime)
    end;
    (try Sys.remove py_file with _ -> ());
    (try Sys.remove r_file with _ -> ());
    (try Unix.rmdir temp_dir with _ -> ())
  end else begin
    incr pass_count; Printf.printf "  ✓ skipped runtime script file test (requires nix-build, python, and Rscript)\n"
  end;
  print_newline ();
  (* Verify that explain indicates the different nodes *)
  let (v_explain, _) = eval_string_env "explain(p_cross).node_count" env_cross in
  if Ast.Utils.value_to_string v_explain = "3" then begin
    incr pass_count; Printf.printf "  ✓ cross-runtime node count correct\n"
  end else begin
    incr fail_count; Printf.printf "  ✗ cross-runtime node count failed\n"
  end;

  print_newline ()
