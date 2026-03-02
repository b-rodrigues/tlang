(* tests/test_pipeline_ops.ml *)
(* Unit tests for Phase 1 and Phase 2 pipeline operations *)

let run_tests pass_count fail_count _eval_string eval_string_env test =

  Printf.printf "Phase 1 — pipeline_to_frame:\n";

  (* Basic usage: should return a DataFrame with the right number of rows *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }; pipeline_to_frame(p) |}
    (Packages.init_env ()) in
  (match v with
   | Ast.VDataFrame { arrow_table; _ } ->
       let nrows = Arrow_table.num_rows arrow_table in
       if nrows = 3 then begin
         incr pass_count; Printf.printf "  ✓ pipeline_to_frame returns one row per node\n"
       end else begin
         incr fail_count;
         Printf.printf "  ✗ pipeline_to_frame row count\n    Expected: 3\n    Got: %d\n" nrows
       end
   | other ->
       incr fail_count;
       Printf.printf "  ✗ pipeline_to_frame should return DataFrame, got: %s\n"
         (Ast.Utils.value_to_string other));

  (* Column names *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1 }; colnames(pipeline_to_frame(p))|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  let expected = {|["name", "runtime", "serializer", "deserializer", "noop", "deps", "depth", "command_type"]|} in
  if result = expected then begin
    incr pass_count; Printf.printf "  ✓ pipeline_to_frame column names correct\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ pipeline_to_frame column names\n    Expected: %s\n    Got: %s\n" expected result
  end;

  (* Depth computation: root nodes have depth 0 *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }
df = pipeline_to_frame(p)
nrow(filter(df, \(row) row.depth == 0))|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = "1" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_to_frame depth: root nodes at depth 0\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ pipeline_to_frame depth\n    Expected: 1\n    Got: %s\n" result
  end;

  (* Type error: not a pipeline *)
  test "pipeline_to_frame rejects non-pipeline"
    {|pipeline_to_frame(42)|}
    {|Error(TypeError: "Function `pipeline_to_frame` expects a Pipeline.")|};

  print_newline ();

  Printf.printf "Phase 2 — filter_node:\n";

  (* filter_node by runtime *)
  let env = Packages.init_env () in
  let (_, env) = eval_string_env
    {|p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, runtime = R)
  c = node(command = <{ 3 }>, runtime = Python)
}|}
    env in
  let (v, _) = eval_string_env
    {|p |> filter_node($runtime == "R") |> pipeline_nodes|}
    env in
  let result = Ast.Utils.value_to_string v in
  if result = {|["b"]|} then begin
    incr pass_count; Printf.printf "  ✓ filter_node by runtime\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ filter_node by runtime\n    Expected: [\"b\"]\n    Got: %s\n" result
  end;

  (* filter_node by noop *)
  let env2 = Packages.init_env () in
  let (_, env2) = eval_string_env
    {|p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, noop = true, runtime = T)
  c = 3
}|}
    env2 in
  let (v, _) = eval_string_env
    {|p |> filter_node($noop == false) |> pipeline_nodes|}
    env2 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["a", "c"]|} then begin
    incr pass_count; Printf.printf "  ✓ filter_node by noop == false\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ filter_node by noop\n    Expected: [\"a\", \"c\"]\n    Got: %s\n" result
  end;

  (* filter_node by depth *)
  let env3 = Packages.init_env () in
  let (_, env3) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }|}
    env3 in
  let (v, _) = eval_string_env
    {|p |> filter_node($depth == 0) |> pipeline_nodes|}
    env3 in
  let result = Ast.Utils.value_to_string v in
  if result = {|["a"]|} then begin
    incr pass_count; Printf.printf "  ✓ filter_node by depth == 0\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ filter_node by depth\n    Expected: [\"a\"]\n    Got: %s\n" result
  end;

  (* filter_node returns empty pipeline when no nodes match *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = 2 }
p |> filter_node($runtime == "Python") |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|[]|} then begin
    incr pass_count; Printf.printf "  ✓ filter_node returns empty pipeline when no match\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ filter_node no match\n    Expected: []\n    Got: %s\n" result
  end;

  (* filter_node type error *)
  test "filter_node rejects non-pipeline"
    {|filter_node(42, $runtime == "T")|}
    {|Error(TypeError: "Function `filter_node` expects a Pipeline as first argument.")|};

  print_newline ();

  Printf.printf "Phase 2 — mutate_node:\n";

  (* mutate_node $noop = true on all nodes *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = 2 }
p2 = p |> mutate_node($noop = true)
pipeline_to_frame(p2) |> filter(\(row) row.noop == true) |> nrow|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ mutate_node sets noop on all nodes\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ mutate_node noop=true\n    Expected: 2\n    Got: %s\n" result
  end;

  (* mutate_node with where clause *)
  let env4 = Packages.init_env () in
  let (_, env4) = eval_string_env
    {|p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, runtime = R)
}|}
    env4 in
  let (v, _) = eval_string_env
    {|p2 = p |> mutate_node($noop = true, where = $runtime == "R")
pipeline_to_frame(p2) |> filter(\(row) row.noop == true) |> nrow|}
    env4 in
  let result = Ast.Utils.value_to_string v in
  if result = "1" then begin
    incr pass_count; Printf.printf "  ✓ mutate_node with where clause scopes changes\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ mutate_node where clause\n    Expected: 1\n    Got: %s\n" result
  end;

  (* mutate_node does not modify original pipeline (immutability) *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1 }
_p2 = p |> mutate_node($noop = true)
pipeline_to_frame(p) |> filter(\(row) row.noop == false) |> nrow|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = "1" then begin
    incr pass_count; Printf.printf "  ✓ mutate_node returns new pipeline (immutability)\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ mutate_node immutability\n    Expected: 1\n    Got: %s\n" result
  end;

  (* mutate_node type error *)
  test "mutate_node rejects non-pipeline"
    {|mutate_node(42, $noop = true)|}
    {|Error(TypeError: "Function `mutate_node` expects a Pipeline as first argument.")|};

  print_newline ();

  Printf.printf "Phase 2 — rename_node:\n";

  (* rename_node basic *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }
p2 = p |> rename_node("a", "alpha")
pipeline_nodes(p2)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["alpha", "b"]|} then begin
    incr pass_count; Printf.printf "  ✓ rename_node renames node\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ rename_node basic\n    Expected: [\"alpha\", \"b\"]\n    Got: %s\n" result
  end;

  (* rename_node rewires edges *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }
p2 = p |> rename_node("a", "alpha")
pipeline_deps(p2)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`alpha`: [], `b`: ["alpha"]}|} then begin
    incr pass_count; Printf.printf "  ✓ rename_node rewires dependency edges\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ rename_node edge rewiring\n    Expected: {`alpha`: [], `b`: [\"alpha\"]}\n    Got: %s\n" result
  end;

  (* rename_node: missing node *)
  test "rename_node errors on missing node"
    {|p = pipeline { a = 1 }; p |> rename_node("x", "y")|}
    {|Error(KeyError: "Node `x` not found in Pipeline.")|};

  (* rename_node: target name already exists *)
  test "rename_node errors when new name already exists"
    {|p = pipeline { a = 1; b = 2 }; p |> rename_node("a", "b")|}
    {|Error(ValueError: "A node named `b` already exists in the Pipeline.")|};

  print_newline ();

  Printf.printf "Phase 2 — select_node:\n";

  (* select_node returns DataFrame with requested columns *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }
colnames(select_node(p, $name, $runtime))|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["name", "runtime"]|} then begin
    incr pass_count; Printf.printf "  ✓ select_node returns DataFrame with requested columns\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ select_node columns\n    Expected: [\"name\", \"runtime\"]\n    Got: %s\n" result
  end;

  (* select_node row count *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = 2; c = 3 }
nrow(select_node(p, $name, $depth))|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = "3" then begin
    incr pass_count; Printf.printf "  ✓ select_node returns one row per node\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ select_node row count\n    Expected: 3\n    Got: %s\n" result
  end;

  (* select_node: unknown field *)
  test "select_node errors on unknown field"
    {|p = pipeline { a = 1 }; select_node(p, $foo)|}
    {|Error(KeyError: "Unknown node metadata field(s): foo. Available: name, runtime, serializer, deserializer, noop, deps, depth, command_type.")|};

  (* select_node: type error *)
  test "select_node rejects non-pipeline"
    {|select_node(42, $name)|}
    {|Error(TypeError: "Function `select_node` expects a Pipeline as first argument.")|};

  print_newline ();

  Printf.printf "Phase 2 — arrange_node:\n";

  (* arrange_node by name ascending *)
  let (v, _) = eval_string_env
    {|p = pipeline { z = 1; a = 2; m = 3 }
p |> arrange_node($name) |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["a", "m", "z"]|} then begin
    incr pass_count; Printf.printf "  ✓ arrange_node by name ascending\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ arrange_node name asc\n    Expected: [\"a\", \"m\", \"z\"]\n    Got: %s\n" result
  end;

  (* arrange_node by name descending *)
  let (v, _) = eval_string_env
    {|p = pipeline { z = 1; a = 2; m = 3 }
p |> arrange_node($name, "desc") |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["z", "m", "a"]|} then begin
    incr pass_count; Printf.printf "  ✓ arrange_node by name descending\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ arrange_node name desc\n    Expected: [\"z\", \"m\", \"a\"]\n    Got: %s\n" result
  end;

  (* arrange_node by depth *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }
p |> arrange_node($depth, "desc") |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["c", "b", "a"]|} then begin
    incr pass_count; Printf.printf "  ✓ arrange_node by depth descending\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ arrange_node depth desc\n    Expected: [\"c\", \"b\", \"a\"]\n    Got: %s\n" result
  end;

  (* arrange_node: bad direction *)
  test "arrange_node errors on bad direction"
    {|p = pipeline { a = 1 }; arrange_node(p, $name, "up")|}
    {|Error(ValueError: "Function `arrange_node` direction must be "asc" or "desc", got "up".")|};

  (* arrange_node: type error *)
  test "arrange_node rejects non-pipeline"
    {|arrange_node(42, $name)|}
    {|Error(TypeError: "Function `arrange_node` expects a Pipeline as first argument.")|};

  print_newline ()
