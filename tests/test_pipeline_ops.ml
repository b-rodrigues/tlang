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

  Printf.printf "Phase 2 — filter_nodes:\n";

  let (v, _) = eval_string_env
    {|p = pipeline {
  bad = 1 / 0
  ok = 42
  downstream = bad + 1
}
filter_nodes(p, !is_na(diagnostics.error)) |> map(\(node) node.name)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["bad", "downstream"]|} then begin
    incr pass_count; Printf.printf "  ✓ filter_nodes auto-wraps diagnostics predicates\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ filter_nodes diagnostics predicate\n    Expected: [\"bad\", \"downstream\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = 2; c = 3 }
pred = \(node) node.name == "b"
filter_nodes(p, pred) |> map(\(node) node.name)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["b"]|} then begin
    incr pass_count; Printf.printf "  ✓ filter_nodes accepts explicit predicate functions\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ filter_nodes explicit predicate\n    Expected: [\"b\"]\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = 2 }
errored_nodes(p)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|[]|} then begin
    incr pass_count; Printf.printf "  ✓ errored_nodes returns an empty list when nothing failed\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ errored_nodes empty result\n    Expected: []\n    Got: %s\n" result
  end;

  let (v, _) = eval_string_env
    {|p = pipeline {
  bad = 1 / 0
  ok = 42
  downstream = bad + 1
}
errored_nodes(p) |> map(\(node) node.name)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["bad", "downstream"]|} then begin
    incr pass_count; Printf.printf "  ✓ errored_nodes returns failing node records\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ errored_nodes failing records\n    Expected: [\"bad\", \"downstream\"]\n    Got: %s\n" result
  end;

  test "filter_nodes rejects non-pipeline"
    {|filter_nodes(42, !is_na(diagnostics.error))|}
    {|Error(TypeError: "Function `filter_nodes` expects a Pipeline as first argument.")|};

  test "filter_nodes errors when predicate does not return Bool"
    {|p = pipeline { a = 1 }; filter_nodes(p, name)|}
    {|Error(TypeError: "Function `filter_nodes` predicate must return Bool, got String.")|};

  test "errored_nodes rejects non-pipeline"
    {|errored_nodes(42)|}
    {|Error(TypeError: "Function `errored_nodes` expects a Pipeline.")|};

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

  (* mutate_node wrong type for noop field *)
  test "mutate_node errors on wrong noop type"
    {|p = pipeline { a = 1 }; mutate_node(p, $noop = "yes")|}
    {|Error(TypeError: "Function `mutate_node`: `noop` must be a Bool, got String.")|};

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

  print_newline ();

  (* ═══════════════════════════════════════════════════════════ *)
  (* Phase 3 — Set Operations                                    *)
  (* ═══════════════════════════════════════════════════════════ *)

  Printf.printf "Phase 3 — union:\n";

  (* union: all nodes present *)
  test "union combines nodes"
    {|p1 = pipeline { a = 1; b = 2 }
p2 = pipeline { c = 3; d = 4 }
p1 |> union(p2) |> pipeline_nodes|}
    {|["a", "b", "c", "d"]|};

  (* union: collision = error *)
  test "union errors on name collision"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { a = 2 }
p1 |> union(p2)|}
    {|Error(ValueError: "Function `union`: name collision(s) detected: a. Use `rename_node` to resolve.")|};

  (* union: type errors *)
  test "union rejects non-pipeline first arg"
    {|union(42, pipeline { a = 1 })|}
    {|Error(TypeError: "Function `union` expects two Pipeline arguments.")|};

  print_newline ();

  Printf.printf "Phase 3 — difference:\n";

  (* difference: removes named nodes *)
  test "difference removes p2 nodes from p1"
    {|p1 = pipeline { a = 1; b = 2; c = 3 }
p2 = pipeline { b = 99 }
p1 |> difference(p2) |> pipeline_nodes|}
    {|["a", "c"]|};

  (* difference: ignores nodes in p2 not in p1 *)
  test "difference ignores missing p2 nodes"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { z = 99 }
p1 |> difference(p2) |> pipeline_nodes|}
    {|["a"]|};

  print_newline ();

  Printf.printf "Phase 3 — intersect:\n";

  (* intersect: keeps only shared names, p1 definitions *)
  test "intersect keeps shared nodes"
    {|p1 = pipeline { a = 1; b = 2; c = 3 }
p2 = pipeline { b = 99; c = 100; d = 4 }
p1 |> intersect(p2) |> pipeline_nodes|}
    {|["b", "c"]|};

  (* intersect: returns empty when no overlap *)
  test "intersect empty when no overlap"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { z = 9 }
p1 |> intersect(p2) |> pipeline_nodes|}
    {|[]|};

  print_newline ();

  Printf.printf "Phase 3 — patch:\n";

  (* patch: updates existing, no additions *)
  let (v, _) = eval_string_env
    {|p1 = pipeline { a = 1; b = 2 }
p2 = pipeline { b = node(command = <{ 99 }>, noop = true, runtime = T) }
p2_patched = p1 |> patch(p2)
pipeline_to_frame(p2_patched) |> filter(\(row) row.noop == true) |> nrow|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = "1" then begin
    incr pass_count; Printf.printf "  ✓ patch updates existing nodes\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ patch updates existing nodes\n    Expected: 1\n    Got: %s\n" result
  end;

  (* patch: no new nodes from p2 *)
  test "patch does not add new nodes"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { b = 2 }
p1 |> patch(p2) |> pipeline_nodes|}
    {|["a"]|};

  print_newline ();

  Printf.printf "Phase 3 — swap:\n";

  (* swap: replaces node command/metadata, preserves edges *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }
p2 = p |> swap("a", node(command = <{ 99 }>, noop = true, runtime = T))
pipeline_to_frame(p2) |> filter(\(row) row.noop == true) |> nrow|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = "1" then begin
    incr pass_count; Printf.printf "  ✓ swap updates node metadata\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ swap updates node metadata\n    Expected: 1\n    Got: %s\n" result
  end;

  (* swap: edges preserved (b still depends on a) *)
  test "swap preserves dependency edges"
    {|p = pipeline { a = 1; b = a + 1 }
p2 = p |> swap("a", node(command = <{ 42 }>, runtime = T))
pipeline_deps(p2)|}
    {|{`a`: [], `b`: ["a"]}|};

  (* swap: missing node *)
  test "swap errors on missing node"
    {|p = pipeline { a = 1 }; p |> swap("z", node(command = <{ 1 }>, runtime = T))|}
    {|Error(KeyError: "Node `z` not found in Pipeline.")|};

  print_newline ();

  Printf.printf "Phase 3 — rewire:\n";

  (* rewire: changes a node's dependencies *)
  let (v, _) = eval_string_env
    {|p = pipeline { data = 1; model = data + 1 }
p2 = p |> rewire("model", replace = list(data = "data"))
pipeline_deps(p2)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  (* The dep should still be data (unchanged replacement) *)
  if result = {|{`data`: [], `model`: ["data"]}|} then begin
    incr pass_count; Printf.printf "  ✓ rewire preserves unchanged deps\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ rewire preserves unchanged deps\n    Expected: {`data`: [], `model`: [\"data\"]}\n    Got: %s\n" result
  end;

  (* rewire: missing node *)
  test "rewire errors on missing node"
    {|p = pipeline { a = 1 }; p |> rewire("z", replace = list(a = "b"))|}
    {|Error(KeyError: "Node `z` not found in Pipeline.")|};

  print_newline ();

  Printf.printf "Phase 3 — prune:\n";

  (* prune: removes leaf nodes *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1; c = 3 }
p |> prune |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  (* b and c are leaves (nothing depends on them), a is depended on by b *)
  (* After prune: only a remains (b depends on a, c has no dependents) *)
  (* Wait: b depends on a, so a is NOT a leaf; b has no dependents so b is leaf; c has no dependents so c is leaf *)
  (* prune removes b and c, leaving just a *)
  if result = {|["a"]|} then begin
    incr pass_count; Printf.printf "  ✓ prune removes leaf nodes\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ prune removes leaf nodes\n    Expected: [\"a\"]\n    Got: %s\n" result
  end;

  (* prune: single node pipeline stays as-is (it's both root and leaf) *)
  test "prune single-node pipeline removes lone leaf node"
    {|p = pipeline { a = 1 }; p |> prune |> pipeline_nodes|}
    {|[]|};

  print_newline ();

  Printf.printf "Phase 3 — upstream_of:\n";

  (* upstream_of: returns node + ancestors *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1; c = b + 1; d = 4 }
p |> upstream_of("c") |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  let contains s sub = try ignore (Str.search_forward (Str.regexp_string sub) s 0); true with Not_found -> false in
  if contains result "\"a\"" && contains result "\"b\"" && contains result "\"c\"" &&
     not (contains result "\"d\"")
  then begin
    incr pass_count; Printf.printf "  ✓ upstream_of includes node and ancestors\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ upstream_of\n    Expected to contain a, b, c (not d)\n    Got: %s\n" result
  end;

  (* upstream_of: missing node *)
  test "upstream_of errors on missing node"
    {|p = pipeline { a = 1 }; p |> upstream_of("z")|}
    {|Error(KeyError: "Node `z` not found in Pipeline.")|};

  print_newline ();

  Printf.printf "Phase 3 — downstream_of:\n";

  (* downstream_of: returns node + descendants *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }
p |> downstream_of("a") |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  let contains s sub = try ignore (Str.search_forward (Str.regexp_string sub) s 0); true with Not_found -> false in
  if contains result "\"a\"" && contains result "\"b\"" && contains result "\"c\"" then begin
    incr pass_count; Printf.printf "  ✓ downstream_of includes node and descendants\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ downstream_of\n    Expected to contain a, b, c\n    Got: %s\n" result
  end;

  (* downstream_of: leaf node returns just itself *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }
p |> downstream_of("b") |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["b"]|} then begin
    incr pass_count; Printf.printf "  ✓ downstream_of leaf returns just itself\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ downstream_of leaf\n    Expected: [\"b\"]\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Phase 3 — subgraph:\n";

  (* subgraph: middle node returns connected component *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }
p |> subgraph("b") |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  let contains s sub = try ignore (Str.search_forward (Str.regexp_string sub) s 0); true with Not_found -> false in
  if contains result "\"a\"" && contains result "\"b\"" && contains result "\"c\"" then begin
    incr pass_count; Printf.printf "  ✓ subgraph of middle node returns full chain\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ subgraph\n    Expected to contain a, b, c\n    Got: %s\n" result
  end;

  (* subgraph: missing node *)
  test "subgraph errors on missing node"
    {|p = pipeline { a = 1 }; p |> subgraph("z")|}
    {|Error(KeyError: "Node `z` not found in Pipeline.")|};

  print_newline ();

  (* ═══════════════════════════════════════════════════════════ *)
  (* Phase 4 — Composition & Inspection                          *)
  (* ═══════════════════════════════════════════════════════════ *)

  Printf.printf "Phase 4 — chain:\n";

  (* chain: wires matching names using split sub-pipelines *)
  (* p_full has a -> b -> c; split into upstream (a) and downstream (b, c with b still dep on a) *)
  let (v, _) = eval_string_env
    {|p_full = pipeline { a = 1; b = a + 1; c = b + 1 }
p1 = p_full |> upstream_of("a")
p2 = p_full |> downstream_of("b")
chain(p1, p2) |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  let contains s sub = try ignore (Str.search_forward (Str.regexp_string sub) s 0); true with Not_found -> false in
  if contains result "a" && contains result "b" && contains result "c" then begin
    incr pass_count; Printf.printf "  ✓ chain merges connected pipelines\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ chain\n    Expected to contain a, b, c\n    Got: %s\n" result
  end;

  (* chain: error when no shared deps *)
  test "chain errors when no matching deps"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { b = 2 }
p1 |> chain(p2)|}
    {|Error(ValueError: "Function `chain`: no shared dependency names found between the two pipelines.")|};

  (* chain: error on collision *)
  test "chain errors on name collision"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { a = 2 }
p1 |> chain(p2)|}
    {|Error(ValueError: "Function `chain`: name collision(s) detected: a. Use `rename_node` to resolve.")|};

  print_newline ();

  Printf.printf "Phase 4 — parallel:\n";

  (* parallel: combines independent pipelines *)
  test "parallel combines pipelines"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { b = 2 }
p1 |> parallel(p2) |> pipeline_nodes|}
    {|["a", "b"]|};

  (* parallel: error on collision *)
  test "parallel errors on name collision"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { a = 2 }
p1 |> parallel(p2)|}
    {|Error(ValueError: "Function `parallel`: name collision(s) detected: a. Use `rename_node` to resolve.")|};

  print_newline ();

  Printf.printf "Phase 4 — inspection API:\n";

  (* pipeline_edges *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }
pipeline_edges(p)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|[["a", "b"]]|} then begin
    incr pass_count; Printf.printf "  ✓ pipeline_edges returns dep pairs\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ pipeline_edges\n    Expected: [[\"a\", \"b\"]]\n    Got: %s\n" result
  end;

  (* pipeline_roots *)
  test "pipeline_roots returns root nodes"
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_roots(p)|}
    {|["a"]|};

  (* pipeline_leaves *)
  test "pipeline_leaves returns leaf nodes"
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_leaves(p)|}
    {|["b"]|};

  (* pipeline_depth *)
  test "pipeline_depth returns max depth"
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }; pipeline_depth(p)|}
    {|2|};

  (* pipeline_cycles: no cycles *)
  test "pipeline_cycles empty for valid DAG"
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_cycles(p)|}
    {|[]|};

  (* pipeline_summary: wraps pipeline_to_frame *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = 2 }; nrow(pipeline_summary(p))|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = "2" then begin
    incr pass_count; Printf.printf "  ✓ pipeline_summary returns full metadata frame\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ pipeline_summary\n    Expected: 2\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Phase 4 — validation:\n";

  (* pipeline_validate: valid pipeline returns empty list *)
  test "pipeline_validate returns empty for valid pipeline"
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_validate(p)|}
    {|[]|};

  (* pipeline_assert: valid pipeline returns itself *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_assert(p) |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["a", "b"]|} then begin
    incr pass_count; Printf.printf "  ✓ pipeline_assert returns pipeline when valid\n"
  end else begin
    incr fail_count;
    Printf.printf "  ✗ pipeline_assert\n    Expected: [\"a\", \"b\"]\n    Got: %s\n" result
  end;

  print_newline ();

  Printf.printf "Phase 4 — pipeline_dot:\n";

  (* pipeline_dot: returns non-empty string *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_dot(p)|}
    (Packages.init_env ()) in
  (match v with
   | Ast.VString s when String.length s > 10 && String.sub s 0 7 = "digraph" ->
       incr pass_count; Printf.printf "  ✓ pipeline_dot returns DOT string\n"
   | other ->
       incr fail_count;
       Printf.printf "  ✗ pipeline_dot\n    Expected: DOT string\n    Got: %s\n"
         (Ast.Utils.value_to_string other));

  print_newline ()
