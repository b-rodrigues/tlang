(* tests/test_pipeline_ops.ml *)
(* Unit tests for Phase 1 and Phase 2 pipeline operations *)

let run_tests pass_count fail_count failures _eval_string eval_string_env test =

  let contains s sub =
    let n = String.length s in
    let m = String.length sub in
    m <= n &&
    let rec loop i =
      i <= n - m && (String.sub s i m = sub || loop (i + 1))
    in
    loop 0
  in

  Printf.printf "Phase 1 — pipeline_to_frame:\n";

  test "pipeline_to_frame returns one row per node"
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }; nrow(pipeline_to_frame(p))|}
    "3";

  test "pipeline_to_frame column names correct"
    {|p = pipeline { a = 1 }; colnames(pipeline_to_frame(p))|}
    {|["name", "runtime", "serializer", "deserializer", "noop", "deps", "depth", "command_type"]|};

  test "pipeline_to_frame depth: root nodes at depth 0"
    {|p = pipeline { a = 1; b = a + 1 }
df = pipeline_to_frame(p)
nrow(filter(df, \(row) row.depth == 0))|}
    "1";

  test "pipeline_to_frame rejects non-pipeline"
    {|pipeline_to_frame(42)|}
    {|Error(TypeError: "[L1:C1] Function `pipeline_to_frame` expects a Pipeline, but got Int.")|};

  print_newline ();

  Printf.printf "Phase 2 — filter_node:\n";

  test "filter_node by runtime"
    {|p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, runtime = R)
  c = node(command = <{ 3 }>, runtime = Python)
}
p |> filter_node($runtime == "R") |> pipeline_nodes|}
    {|["b"]|};

  test "filter_node by noop == false"
    {|p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, noop = true, runtime = T)
  c = 3
}
p |> filter_node($noop == false) |> pipeline_nodes|}
    {|["a", "c"]|};

  test "filter_node by depth == 0"
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }
p |> filter_node($depth == 0) |> pipeline_nodes|}
    {|["a"]|};

  test "filter_node returns empty pipeline when no match"
    {|p = pipeline { a = 1; b = 2 }
p |> filter_node($runtime == "Python") |> pipeline_nodes|}
    {|[]|};

  test "filter_node rejects non-pipeline"
    {|filter_node(42, $runtime == "T")|}
    {|Error(TypeError: "Function `filter_node` expects a Pipeline as first argument.")|};

  test "filter_node can filter on diagnostics errors"
    {|p = pipeline {
  bad = 1 / 0
  ok = 42
  downstream = bad + 1
}
p |> filter_node(!is_na($diagnostics.error)) |> pipeline_nodes|}
    {|[]|};

  test "filter_node can keep nodes without diagnostics errors"
    {|p = pipeline {
  bad = 1 / 0
  ok = 42
  downstream = bad + 1
}
p |> filter_node(is_na($diagnostics.error)) |> pipeline_nodes|}
    {|["bad", "ok", "downstream"]|};

  print_newline ();

  Printf.printf "Phase 2 — which_nodes:\n";

  test "which_nodes auto-wraps diagnostics predicates"
    {|p = pipeline {
  bad = 1 / 0
  ok = 42
  downstream = bad + 1
}
which_nodes(p, !is_na(diagnostics.error)) |> map(\(node) node.name)|}
    {|[]|};

  test "which_nodes accepts explicit predicate functions"
    {|p = pipeline { a = 1; b = 2; c = 3 }
pred = \(node) node.name == "b"
which_nodes(p, pred) |> map(\(node) node.name)|}
    {|["b"]|};

  test "errored_nodes returns an empty list when nothing failed"
    {|p = pipeline { a = 1; b = 2 }
errored_nodes(p)|}
    {|[]|};

  test "errored_nodes returns failing node records"
    {|p = pipeline {
  bad = 1 / 0
  ok = 42
  downstream = bad + 1
}
errored_nodes(p) |> map(\(node) node.name)|}
    {|[]|};

  test "which_nodes rejects non-pipeline"
    {|which_nodes(42, !is_na(diagnostics.error))|}
    {|Error(TypeError: "[L1:C1] Function `which_nodes` expects a Pipeline as first argument, but got Int.")|};

  test "which_nodes errors when predicate does not return Bool"
    {|p = pipeline { a = 1 }; which_nodes(p, name)|}
    {|Error(TypeError: "Function `which_nodes` predicate must return Bool, got String.")|};

  test "errored_nodes rejects non-pipeline"
    {|errored_nodes(42)|}
    {|Error(TypeError: "[L1:C1] Function `errored_nodes` expects a Pipeline, but got Int.")|};

  print_newline ();

  Printf.printf "Phase 2 — mutate_node:\n";

  test "mutate_node sets noop on all nodes"
    {|p = pipeline { a = 1; b = 2 }
p2 = p |> mutate_node($noop = true)
pipeline_to_frame(p2) |> filter(\(row) row.noop == true) |> nrow|}
    "2";

  test "mutate_node with where clause scopes changes"
    {|p = pipeline {
  a = 1
  b = node(command = <{ 2 }>, runtime = R)
}
p2 = p |> mutate_node($noop = true, where = $runtime == "R")
pipeline_to_frame(p2) |> filter(\(row) row.noop == true) |> nrow|}
    "1";

  test "mutate_node returns new pipeline (immutability)"
    {|p = pipeline { a = 1 }
_p2 = p |> mutate_node($noop = true)
pipeline_to_frame(p) |> filter(\(row) row.noop == false) |> nrow|}
    "1";

  test "mutate_node rejects non-pipeline"
    {|mutate_node(42, $noop = true)|}
    {|Error(TypeError: "Function `mutate_node` expects a Pipeline as first argument.")|};

  test "mutate_node errors on wrong noop type"
    {|p = pipeline { a = 1 }; mutate_node(p, $noop = "yes")|}
    {|Error(TypeError: "Function `mutate_node`: `noop` must be a Bool, got String.")|};

  test "mutate_node sets functions on all nodes"
    {|p = pipeline { a = node(command = 1, functions = ["x.R"]); b = node(command = 2) }
      p2 = p |> mutate_node($functions = ["new.R"])
      length(pipeline_node_options(p2, "a").functions)|}
    "1";

  test "mutate_node clears functions with NA"
    {|p = pipeline { a = node(command = 1, functions = ["x.R", "y.R"]) }
      p2 = p |> mutate_node($functions = na())
      length(pipeline_node_options(p2, "a").functions)|}
    "0";

  test "mutate_node sets include on all nodes"
    {|p = pipeline { a = node(command = 1, include = ["x.csv"]) }
      p2 = p |> mutate_node($include = ["shared.R"])
      length(pipeline_node_options(p2, "a").include)|}
    "1";

  test "mutate_node sets env_vars"
    {|p = pipeline { a = node(command = 1, env_vars = [OLD: "val"]) }
      p2 = p |> mutate_node($env_vars = [FOO: "bar", BAZ: "qux"])
      length(pipeline_node_options(p2, "a").env_vars)|}
    "2";

  test "mutate_node clears env_vars with NA"
    {|p = pipeline { a = node(command = 1, env_vars = [OLD: "val"]) }
      p2 = p |> mutate_node($env_vars = na())
      length(pipeline_node_options(p2, "a").env_vars)|}
    "0";

  test "mutate_node sets args"
    {|p = pipeline { a = node(command = 1) }
      p2 = p |> mutate_node($args = [mode: "batch"])
      length(pipeline_node_options(p2, "a").args)|}
    "1";

  test "mutate_node sets shell"
    {|p = pipeline { a = node(command = 1) }
      p2 = p |> mutate_node($shell = "zsh")
      pipeline_node_options(p2, "a").shell|}
    "zsh";

  test "mutate_node clears shell with NA"
    {|p = pipeline { a = node(command = 1) }
      p2 = p |> mutate_node($shell = na())
      pipeline_node_options(p2, "a").shell|}
    "NA";

  test "mutate_node sets shell_args"
    {|p = pipeline { a = node(command = 1, shell_args = ["-x"]) }
      p2 = p |> mutate_node($shell_args = ["--mutated"])
      length(pipeline_node_options(p2, "a").shell_args)|}
    "1";

  test "mutate_node sets flake"
    {|p = pipeline { a = node(command = 1) }
      p2 = p |> mutate_node($flake = "path:./custom")
      pipeline_node_options(p2, "a").flake|}
    "path:./custom";

  test "mutate_node clears flake with NA"
    {|p = pipeline { a = node(command = 1, flake = "path:./old") }
      p2 = p |> mutate_node($flake = na())
      pipeline_node_options(p2, "a").flake|}
    "NA";

  test "mutate_node errors on wrong functions type"
    {|p = pipeline { a = 1 }; mutate_node(p, $functions = 42)|}
    {|Error(TypeError: "Function `mutate_node`: `functions` must be a List of Strings or Symbols, got Int.")|};

  test "mutate_node errors on wrong env_vars type"
    {|p = pipeline { a = 1 }; mutate_node(p, $env_vars = "not_a_dict")|}
    {|Error(TypeError: "Function `mutate_node`: `env_vars` must be a Dict, got String.")|};

  test "mutate_node errors on wrong shell type"
    {|p = pipeline { a = 1 }; mutate_node(p, $shell = 42)|}
    {|Error(TypeError: "Function `mutate_node`: `shell` must be a String, got Int.")|};

  test "mutate_node where clause scopes new fields"
    {|p = pipeline { a = node(command = 1, functions = ["a.R"]); b = node(command = 2, functions = ["b.R"]) }
      p2 = p |> mutate_node($functions = ["only-b.R"], where = $name == "b")
      length(pipeline_node_options(p2, "a").functions)|}
    "1";

  print_newline ();

  Printf.printf "Phase 2 — rename_node:\n";

  test "rename_node renames node"
    {|p = pipeline { a = 1; b = a + 1 }
p2 = p |> rename_node("a", "alpha")
pipeline_nodes(p2)|}
    {|["alpha", "b"]|};

  test "rename_node rewires dependency edges"
    {|p = pipeline { a = 1; b = a + 1 }
p2 = p |> rename_node("a", "alpha")
pipeline_deps(p2)|}
    {|{`alpha`: [], `b`: ["alpha"]}|};

  test "rename_node errors on missing node"
    {|p = pipeline { a = 1 }; p |> rename_node("x", "y")|}
    {|Error(KeyError: "Node `x` not found in Pipeline.")|};

  test "rename_node errors when new name already exists"
    {|p = pipeline { a = 1; b = 2 }; p |> rename_node("a", "b")|}
    {|Error(ValueError: "A node named `b` already exists in the Pipeline.")|};

  test "rename_node rejects reserved new name"
    {|p = pipeline { a = 1 }; p |> rename_node("a", "n")|}
    {|Error(ValueError: "Node `n` is reserved: `n` is a builtin function. Node names cannot collide with builtin functions or runtime symbols. Choose a different node name.")|};

  print_newline ();

  Printf.printf "Phase 2 — select_node:\n";

  test "select_node returns DataFrame with requested columns"
    {|p = pipeline { a = 1; b = a + 1 }
colnames(select_node(p, $name, $runtime))|}
    {|["name", "runtime"]|};

  test "select_node returns one row per node"
    {|p = pipeline { a = 1; b = 2; c = 3 }
nrow(select_node(p, $name, $depth))|}
    "3";

  test "select_node errors on unknown field"
    {|p = pipeline { a = 1 }; select_node(p, $foo)|}
    {|Error(KeyError: "Unknown node metadata field(s): foo. Available: name, runtime, serializer, deserializer, noop, deps, depth, command_type.")|};

  test "select_node rejects non-pipeline"
    {|select_node(42, $name)|}
    {|Error(TypeError: "[L1:C1] Function `select_node` expects a Pipeline as first argument, but got Int.")|};

  print_newline ();

  Printf.printf "Phase 2 — arrange_node:\n";

  test "arrange_node by name ascending"
    {|p = pipeline { z = 1; a = 2; m = 3 }
p |> arrange_node($name) |> pipeline_nodes|}
    {|["a", "m", "z"]|};

  test "arrange_node by name descending"
    {|p = pipeline { z = 1; a = 2; m = 3 }
p |> arrange_node($name, "desc") |> pipeline_nodes|}
    {|["z", "m", "a"]|};

  test "arrange_node by depth descending"
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }
p |> arrange_node($depth, "desc") |> pipeline_nodes|}
    {|["c", "b", "a"]|};

  test "arrange_node errors on bad direction"
    {|p = pipeline { a = 1 }; arrange_node(p, $name, "up")|}
    {|Error(ValueError: "Function `arrange_node` direction must be "asc" or "desc", got "up".")|};

  test "arrange_node rejects non-pipeline"
    {|arrange_node(42, $name)|}
    {|Error(TypeError: "Function `arrange_node` expects a Pipeline as first argument.")|};

  print_newline ();

  (* ═══════════════════════════════════════════════════════════ *)
  (* Phase 3 — Set Operations                                    *)
  (* ═══════════════════════════════════════════════════════════ *)

  Printf.printf "Phase 3 — union:\n";

  test "union combines nodes"
    {|p1 = pipeline { a = 1; b = 2 }
p2 = pipeline { c = 3; d = 4 }
p1 |> union(p2) |> pipeline_nodes|}
    {|["a", "b", "c", "d"]|};

  test "union errors on name collision"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { a = 2 }
p1 |> union(p2)|}
    {|Error(ValueError: "Function `union`: name collision(s) detected: a. Use `rename_node` to resolve.")|};

  test "union rejects non-pipeline first arg"
    {|union(42, pipeline { a = 1 })|}
    {|Error(TypeError: "Function `union` expects two Pipeline arguments.")|};

  print_newline ();

  Printf.printf "Phase 3 — difference:\n";

  test "difference removes p2 nodes from p1"
    {|p1 = pipeline { a = 1; b = 2; c = 3 }
p2 = pipeline { b = 99 }
p1 |> difference(p2) |> pipeline_nodes|}
    {|["a", "c"]|};

  test "difference ignores missing p2 nodes"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { z = 99 }
p1 |> difference(p2) |> pipeline_nodes|}
    {|["a"]|};

  print_newline ();

  Printf.printf "Phase 3 — intersect:\n";

  test "intersect keeps shared nodes"
    {|p1 = pipeline { a = 1; b = 2; c = 3 }
p2 = pipeline { b = 99; c = 100; d = 4 }
p1 |> intersect(p2) |> pipeline_nodes|}
    {|["b", "c"]|};

  test "intersect empty when no overlap"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { z = 9 }
p1 |> intersect(p2) |> pipeline_nodes|}
    {|[]|};

  print_newline ();

  Printf.printf "Phase 3 — patch:\n";

  test "patch updates existing nodes"
    {|p1 = pipeline { a = 1; b = 2 }
p2 = pipeline { b = node(command = <{ 99 }>, noop = true, runtime = T) }
p2_patched = p1 |> patch(p2)
pipeline_to_frame(p2_patched) |> filter(\(row) row.noop == true) |> nrow|}
    "1";

  test "patch does not add new nodes"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { b = 2 }
p1 |> patch(p2) |> pipeline_nodes|}
    {|["a"]|};

  print_newline ();

  Printf.printf "Phase 3 — swap:\n";

  test "swap updates node metadata"
    {|p = pipeline { a = 1; b = a + 1 }
p2 = p |> swap("a", node(command = <{ 99 }>, noop = true, runtime = T))
pipeline_to_frame(p2) |> filter(\(row) row.noop == true) |> nrow|}
    "1";

  test "swap preserves dependency edges"
    {|p = pipeline { a = 1; b = a + 1 }
p2 = p |> swap("a", node(command = <{ 42 }>, runtime = T))
pipeline_deps(p2)|}
    {|{`a`: [], `b`: ["a"]}|};

  test "swap errors on missing node"
    {|p = pipeline { a = 1 }; p |> swap("z", node(command = <{ 1 }>, runtime = T))|}
    {|Error(KeyError: "Node `z` not found in Pipeline.")|};

  print_newline ();

  Printf.printf "Phase 3 — rewire:\n";

  test "rewire preserves unchanged deps"
    {|p = pipeline { data = 1; model = data + 1 }
p2 = p |> rewire("model", replace = [data: "data"])
pipeline_deps(p2)|}
    {|{`data`: [], `model`: ["data"]}|};

  test "rewire errors on missing node"
    {|p = pipeline { a = 1 }; p |> rewire("z", replace = [a: "b"])|}
    {|Error(KeyError: "Node `z` not found in Pipeline.")|};

  test "rewire rejects list(...) form loudly (no silent no-op)"
    {|p = pipeline { data = 1; model = data + 1 }; p |> rewire("model", replace = list(data = "data_v2"))|}
    "Error(NameError: \"Name `list` is not defined.\nDid you mean `nest`?\")";

  test "rewire errors when replace is missing"
    {|p = pipeline { data = 1; model = data + 1 }; p |> rewire("model")|}
    {|Error(TypeError: "Function `rewire` expects a `replace` named argument mapping old dependency names to new ones.")|};

  test "rewire errors on non-dict replace value"
    {|p = pipeline { data = 1; model = data + 1 }; p |> rewire("model", replace = 42)|}
    {|Error(TypeError: "Function `rewire` expects `replace` to be a Dict or named List of node-name strings, but got Int.")|};

  test "rewire errors on non-string dict entry"
    {|p = pipeline { data = 1; model = data + 1 }; p |> rewire("model", replace = [data: 42])|}
    {|Error(TypeError: "Function `rewire` expects `replace` entries to map node names to node-name strings, but got Int.")|};

  print_newline ();

  Printf.printf "Phase 3 — prune:\n";

  test "prune removes leaf nodes"
    {|p = pipeline { a = 1; b = a + 1; c = 3 }
p |> prune |> pipeline_nodes|}
    {|["a"]|};

  test "prune single-node pipeline removes lone leaf node"
    {|p = pipeline { a = 1 }; p |> prune |> pipeline_nodes|}
    {|[]|};

  print_newline ();

  Printf.printf "Phase 3 — upstream_of:\n";

  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1; c = b + 1; d = 4 }
p |> upstream_of("c") |> pipeline_nodes|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if contains result "\"a\"" && contains result "\"b\"" && contains result "\"c\"" &&
     not (contains result "\"d\"")
  then begin
    incr pass_count;
    Printf.printf "  ✓ upstream_of includes node and ancestors\n"
  end else begin
    incr fail_count;
    let msg = Printf.sprintf "  ✗ upstream_of includes node and ancestors\n    Got: %s\n" result in
    failures := msg :: !failures;
    Printf.printf "%s" msg
  end;

  test "upstream_of errors on missing node"
    {|p = pipeline { a = 1 }; p |> upstream_of("z")|}
    {|Error(KeyError: "Node `z` not found in Pipeline.")|};

  print_newline ();

  Printf.printf "Phase 3 — downstream_of:\n";

  test "downstream_of includes node and descendants"
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }
p |> downstream_of("a") |> pipeline_nodes|}
    {|.*"a".*"b".*"c".*|};

  test "downstream_of leaf returns just itself"
    {|p = pipeline { a = 1; b = a + 1 }
p |> downstream_of("b") |> pipeline_nodes|}
    {|["b"]|};

  print_newline ();

  Printf.printf "Phase 3 — subgraph:\n";

  test "subgraph of middle node returns full chain"
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }
p |> subgraph("b") |> pipeline_nodes|}
    {|.*"a".*"b".*"c".*|};

  test "subgraph errors on missing node"
    {|p = pipeline { a = 1 }; p |> subgraph("z")|}
    {|Error(KeyError: "Node `z` not found in Pipeline.")|};

  print_newline ();

  (* ═══════════════════════════════════════════════════════════ *)
  (* Phase 4 — Composition & Inspection                          *)
  (* ═══════════════════════════════════════════════════════════ *)

  Printf.printf "Phase 4 — chain:\n";

  test "chain merges connected pipelines"
    {|p_full = pipeline { a = 1; b = a + 1; c = b + 1 }
p1 = p_full |> upstream_of("a")
p2 = p_full |> downstream_of("b")
chain(p1, p2) |> pipeline_nodes|}
    {|.*"a".*"b".*"c".*|};

  test "chain errors when no matching deps"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { b = 2 }
p1 |> chain(p2)|}
    {|Error(ValueError: "Function `chain`: no shared dependency names found between the two pipelines.")|};

  test "chain errors on name collision"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { a = 2 }
p1 |> chain(p2)|}
    {|Error(ValueError: "Function `chain`: name collision(s) detected: a. Use `rename_node` to resolve.")|};

  print_newline ();

  Printf.printf "Phase 4 — parallel:\n";

  test "parallel combines pipelines"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { b = 2 }
p1 |> parallel(p2) |> pipeline_nodes|}
    {|["a", "b"]|};

  test "parallel errors on name collision"
    {|p1 = pipeline { a = 1 }
p2 = pipeline { a = 2 }
p1 |> parallel(p2)|}
    {|Error(ValueError: "Function `parallel`: name collision(s) detected: a. Use `rename_node` to resolve.")|};

  print_newline ();

  Printf.printf "Phase 4 — inspection API:\n";

  test "pipeline_edges returns dep pairs"
    {|p = pipeline { a = 1; b = a + 1 }
pipeline_edges(p)|}
    {|[["a", "b"]]|};

  test "pipeline_roots returns root nodes"
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_roots(p)|}
    {|["a"]|};

  test "pipeline_leaves returns leaf nodes"
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_leaves(p)|}
    {|["b"]|};

  test "pipeline_depth returns max depth"
    {|p = pipeline { a = 1; b = a + 1; c = b + 1 }; pipeline_depth(p)|}
    {|2|};

  test "pipeline_cycles empty for valid DAG"
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_cycles(p)|}
    {|[]|};

  test "pipeline_to_frame returns full metadata frame"
    {|p = pipeline { a = 1; b = 2 }; nrow(pipeline_to_frame(p))|}
    "2";

  print_newline ();

  Printf.printf "Phase 4 — validation:\n";

  test "pipeline_validate returns empty for valid pipeline"
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_validate(p)|}
    {|[]|};

  test "pipeline_assert returns pipeline when valid"
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_assert(p) |> pipeline_nodes|}
    {|["a", "b"]|};

  test "pipeline_validate reports missing function file"
    {|p = pipeline { a = rn(command = <{ 1 }>, functions = "nonexistent.R") }; pipeline_validate(p)|}
    "missing from the file system: nonexistent.R";

  test "pipeline_validate reports unknown runtime"
    {|p = pipeline { a = rn(command = <{ 1 }>, runtime = "bogus") }; pipeline_validate(p)|}
    {|Node `a` uses unknown runtime `bogus`|};

  test "pipeline_validate reports serializer coherence mismatch"
    {|p = pipeline {
         x = rn(command = <{ 1 }>, serializer = ^csv);
         y = rn(command = <{ x + 1 }>, deserializer = ^ipc, deps = ["x"])
       }; pipeline_validate(p)|}
    "expects format `ipc` for dependency `x`";

  test "pipeline_validate reports multi-dep single strategy"
    {|p = pipeline {
         x = rn(command = <{ 1 }>, serializer = ^csv);
         y = rn(command = <{ 2 }>, serializer = ^json);
         z = rn(command = <{ 3 }>, deps = ["x", "y"], deserializer = ^json)
       }; pipeline_validate(p)|}
    "single deserializer strategy";

  test "pipeline_validate accepts shell node consuming json producer"
    {|p = pipeline {
         dep_node = node(command = <{ "hello" }>, serializer = ^json);
         sh_node = shn(command = <{ cat "$T_INPUT_dep_node" }>, deps = ["dep_node"])
       }; pipeline_validate(p)|}
    {|[]|};

  test "pipeline_validate accepts typed consumer reading shell text producer"
    {|p = pipeline {
         awk_node = shn(command = <{ echo "variable,value" }>);
         final_summary = node(command = <{ awk_node |> head(1) }>,
                              deserializer = [awk_node: ^csv], deps = ["awk_node"])
       }; pipeline_validate(p)|}
    {|[]|};

  test "pipeline_validate accepts shell node with multiple deps"
    {|p = pipeline {
         a = node(command = <{ 1 }>, serializer = ^json);
         b = node(command = <{ 2 }>, serializer = ^csv);
         sh_out = shn(command = <{ cat "$T_INPUT_a" "$T_INPUT_b" }>, deps = ["a", "b"])
       }; pipeline_validate(p)|}
    {|[]|};

  test "pipeline_validate reports bin on non-fetchurl node"
    {|p = pipeline { a = rn(command = <{ 1 }>, serializer = ^bin) }; pipeline_validate(p)|}
    "only supported for fetchurl nodes";

  test "pipeline_validate aggregates multiple errors"
    {|p = pipeline {
         a = rn(command = <{ 1 }>, functions = "missing1.R", runtime = "bogus")
       }; length(pipeline_validate(p))|}
    "2";

  test "pipeline_assert throws first validation error"
    {|p = pipeline { a = rn(command = <{ 1 }>, runtime = "bogus") }; pipeline_assert(p)|}
    "unknown runtime `bogus`";

  print_newline ();

  Printf.printf "Phase 4 — pipeline_to_dot:\n";

  (* pipeline_to_dot: returns DOT string — needs OCaml string inspection *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_to_dot(p)|}
    (Packages.init_env ()) in
  (match v with
   | Ast.VString s when String.length s > 10 && String.sub s 0 7 = "digraph" ->
       incr pass_count; Printf.printf "  ✓ pipeline_to_dot returns DOT string\n"
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ pipeline_to_dot\n    Expected: DOT string\n    Got: %s\n"
         (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* Duplicate check (original had this) *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_to_dot(p)|}
    (Packages.init_env ()) in
  (match v with
   | Ast.VString s when String.length s > 10 && String.sub s 0 7 = "digraph" ->
       incr pass_count; Printf.printf "  ✓ pipeline_to_dot returns DOT string\n"
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ pipeline_to_dot\n    Expected: DOT string\n    Got: %s\n"
         (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* pipeline_to_mermaid: returns Mermaid string — needs OCaml string inspection *)
  let (v, _) = eval_string_env
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_to_mermaid(p)|}
    (Packages.init_env ()) in
  (match v with
    | Ast.VString s when String.length s > 10 && contains s "graph LR" ->
        incr pass_count; Printf.printf "  ✓ pipeline_to_mermaid returns Mermaid string\n"
    | other ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_mermaid\n    Expected: Mermaid string containing 'graph LR'\n    Got: %s\n"
         (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* pipeline_to_mermaid collision avoidance: needs substring checking *)
  let (v, _) = eval_string_env
    {|p = pipeline { etl_raw = 1; raw = 2 } |> rename_node("raw", "etl.raw"); pipeline_to_mermaid(p)|}
    (Packages.init_env ()) in
  (match v with
       | Ast.VString s ->
       if contains s "etl_raw[\"etl_raw [" && contains s "etl_raw__2[\"etl.raw [" then begin
         incr pass_count; Printf.printf "  ✓ pipeline_to_mermaid avoids ID collisions\n"
       end else begin
         incr fail_count;
         let msg = Printf.sprintf "  ✗ pipeline_to_mermaid collision avoidance\n    Expected to find unique IDs etl_raw and etl_raw__2\n    Got: %s\n" s in
         failures := msg :: !failures;
         Printf.printf "%s" msg
       end
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ pipeline_to_mermaid collision avoidance type\n    Got: %s\n" (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* pipeline_to_dot with MetaPipeline *)
  let (v, _) = eval_string_env
    {|p_etl = pipeline { raw = 1; clean = raw + 1 };
      p_stats = pipeline { summary_node = 2 };
      meta = pipeline_of { etl = p_etl; stats = p_stats };
      pipeline_to_dot(meta)|}
    (Packages.init_env ()) in
  (match v with
   | Ast.VString s when String.length s > 10 && String.sub s 0 7 = "digraph" ->
       incr pass_count; Printf.printf "  ✓ pipeline_to_dot on MetaPipeline returns DOT string\n"
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ pipeline_to_dot on MetaPipeline\n    Expected: DOT string\n    Got: %s\n"
         (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* pipeline_to_mermaid with MetaPipeline *)
  let (v, _) = eval_string_env
    {|p_etl = pipeline { raw = 1; clean = raw + 1 };
      p_stats = pipeline { summary_node = 2 };
      meta = pipeline_of { etl = p_etl; stats = p_stats };
      pipeline_to_mermaid(meta)|}
    (Packages.init_env ()) in
  (match v with
    | Ast.VString s when String.length s > 10 && contains s "graph LR" ->
        incr pass_count; Printf.printf "  ✓ pipeline_to_mermaid on MetaPipeline returns Mermaid string\n"
     | other ->
         incr fail_count;
         let msg = Printf.sprintf "  ✗ pipeline_to_mermaid on MetaPipeline\n    Expected: Mermaid string containing 'graph LR'\n    Got: %s\n"
          (Ast.Utils.value_to_string other) in
        failures := msg :: !failures;
        Printf.printf "%s" msg);

   (* pipeline_to_mermaid with MetaPipeline renders subgraph blocks by default *)
   let (v, _) = eval_string_env
     {|p_etl = pipeline { raw = 1; clean = raw + 1 };
       p_stats = pipeline { summary_node = 2 };
       meta = pipeline_of { etl = p_etl; stats = p_stats };
       pipeline_to_mermaid(meta)|}
     (Packages.init_env ()) in
   (match v with
    | Ast.VString s when contains s "subgraph etl" && contains s "subgraph stats" ->
        incr pass_count; Printf.printf "  ✓ pipeline_to_mermaid MetaPipeline renders subgraph blocks\n"
    | Ast.VString s ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_mermaid MetaPipeline subgraphs\n    Expected subgraph blocks, got:\n%s\n" s in
        failures := msg :: !failures;
        Printf.printf "%s" msg
    | other ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_mermaid MetaPipeline subgraphs type\n    Got: %s\n" (Ast.Utils.value_to_string other) in
        failures := msg :: !failures;
        Printf.printf "%s" msg);

   (* pipeline_to_mermaid with flatten=true returns flat output (no subgraph) *)
   let (v, _) = eval_string_env
     {|p_etl = pipeline { raw = 1; clean = raw + 1 };
       p_stats = pipeline { summary_node = 2 };
       meta = pipeline_of { etl = p_etl; stats = p_stats };
       pipeline_to_mermaid(meta, flatten = true)|}
     (Packages.init_env ()) in
   (match v with
    | Ast.VString s when not (contains s "subgraph") && contains s "etl.raw" ->
        incr pass_count; Printf.printf "  ✓ pipeline_to_mermaid flatten=true omits subgraph blocks\n"
    | Ast.VString s ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_mermaid flatten=true\n    Expected flat output without subgraph, got:\n%s\n" s in
        failures := msg :: !failures;
        Printf.printf "%s" msg
    | other ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_mermaid flatten=true type\n    Got: %s\n" (Ast.Utils.value_to_string other) in
        failures := msg :: !failures;
        Printf.printf "%s" msg);

   (* pipeline_to_dot with MetaPipeline renders subgraph clusters by default *)
   let (v, _) = eval_string_env
     {|p_etl = pipeline { raw = 1; clean = raw + 1 };
       p_stats = pipeline { summary_node = 2 };
       meta = pipeline_of { etl = p_etl; stats = p_stats };
       pipeline_to_dot(meta)|}
     (Packages.init_env ()) in
   (match v with
    | Ast.VString s when contains s "subgraph cluster_etl" && contains s "subgraph cluster_stats" ->
        incr pass_count; Printf.printf "  ✓ pipeline_to_dot MetaPipeline renders subgraph clusters\n"
    | Ast.VString s ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_dot MetaPipeline subgraph clusters\n    Expected cluster subgraphs, got:\n%s\n" s in
        failures := msg :: !failures;
        Printf.printf "%s" msg
    | other ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_dot MetaPipeline subgraph clusters type\n    Got: %s\n" (Ast.Utils.value_to_string other) in
        failures := msg :: !failures;
        Printf.printf "%s" msg);

   (* pipeline_to_dot with flatten=true omits subgraph clusters *)
   let (v, _) = eval_string_env
     {|p_etl = pipeline { raw = 1; clean = raw + 1 };
       p_stats = pipeline { summary_node = 2 };
       meta = pipeline_of { etl = p_etl; stats = p_stats };
       pipeline_to_dot(meta, flatten = true)|}
     (Packages.init_env ()) in
   (match v with
    | Ast.VString s when not (contains s "subgraph") ->
        incr pass_count; Printf.printf "  ✓ pipeline_to_dot flatten=true omits cluster subgraphs\n"
    | Ast.VString s ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_dot flatten=true\n    Expected flat output without subgraph, got:\n%s\n" s in
        failures := msg :: !failures;
        Printf.printf "%s" msg
    | other ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_dot flatten=true type\n    Got: %s\n" (Ast.Utils.value_to_string other) in
        failures := msg :: !failures;
        Printf.printf "%s" msg);

   (* pipeline_to_mermaid subgraph with cross-pipeline dependency *)
   let (v, _) = eval_string_env
     {|p_etl = pipeline { raw = 1; clean = raw + 1 };
       p_stats = pipeline { summary_node = etl.clean + 2 };
       meta = pipeline_of { etl = p_etl; stats = p_stats };
       pipeline_to_mermaid(meta)|}
     (Packages.init_env ()) in
   (match v with
    | Ast.VString s when contains s "subgraph etl" && contains s "subgraph stats" && contains s "etl_clean -->" && contains s "stats_summary_node" ->
        incr pass_count; Printf.printf "  ✓ pipeline_to_mermaid cross-subgraph edge rendered correctly\n"
    | Ast.VString s ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_mermaid cross-subgraph edge\n    Expected subgraphs with cross edge, got:\n%s\n" s in
        failures := msg :: !failures;
        Printf.printf "%s" msg
    | other ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_mermaid cross-subgraph edge type\n    Got: %s\n" (Ast.Utils.value_to_string other) in
        failures := msg :: !failures;
        Printf.printf "%s" msg);

   (* pipeline_to_mermaid auto-detects project name from tproject.toml *)
   let (v, _) = eval_string_env
     {|p = pipeline { a = 1; b = a + 1 }; pipeline_to_mermaid(p)|}
     (Packages.init_env ()) in
   (match v with
    | Ast.VString s when contains s "Dependency Graph of Project" && contains s "tlang" ->
        incr pass_count; Printf.printf "  ✓ pipeline_to_mermaid auto-detects project name\n"
    | Ast.VString s ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_mermaid auto-detect title\n    Expected project name in title, got:\n%s\n" s in
        failures := msg :: !failures;
        Printf.printf "%s" msg
    | other ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_mermaid auto-detect title type\n    Got: %s\n" (Ast.Utils.value_to_string other) in
        failures := msg :: !failures;
        Printf.printf "%s" msg);

   (* pipeline_to_mermaid with explicit title argument *)
   let (v, _) = eval_string_env
     {|p = pipeline { a = 1; b = a + 1 }; pipeline_to_mermaid(p, title = "Custom Title")|}
     (Packages.init_env ()) in
   (match v with
    | Ast.VString s when contains s "tlang-title: Custom Title" ->
        incr pass_count; Printf.printf "  ✓ pipeline_to_mermaid with custom title\n"
    | Ast.VString s ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_mermaid custom title\n    Expected title, got:\n%s\n" s in
        failures := msg :: !failures;
        Printf.printf "%s" msg
    | other ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_mermaid custom title type\n    Got: %s\n" (Ast.Utils.value_to_string other) in
        failures := msg :: !failures;
        Printf.printf "%s" msg);

   (* pipeline_to_dot with explicit title argument *)
   let (v, _) = eval_string_env
     {|p = pipeline { a = 1; b = a + 1 }; pipeline_to_dot(p, title = "Custom DOT Title")|}
     (Packages.init_env ()) in
   (match v with
    | Ast.VString s when contains s "Custom DOT Title" ->
        incr pass_count; Printf.printf "  ✓ pipeline_to_dot with custom title\n"
    | Ast.VString s ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_dot custom title\n    Expected title, got:\n%s\n" s in
        failures := msg :: !failures;
        Printf.printf "%s" msg
    | other ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_to_dot custom title type\n    Got: %s\n" (Ast.Utils.value_to_string other) in
        failures := msg :: !failures;
        Printf.printf "%s" msg);

  Printf.printf "Phase 4 — suppress_warnings:\n";

  test "suppress_warnings passthrough"
    "suppress_warnings(42)"
    "42";

  test "suppress_warnings with string"
    {|suppress_warnings("hello")|}
    {|"hello"|};

  test "suppress_warnings with NA"
    "suppress_warnings(NA)"
    "NA";

  test "suppress_warnings rejects too many args"
    "suppress_warnings(1, 2)"
    {|Error(ArityError: "Function `suppress_warnings` expects 1 arguments but received 2.")|};

  Printf.printf "Phase 4 — trace_nodes and pipeline_print:\n";

  test "trace_nodes returns NA"
    {|p = pipeline { a = 1; b = a + 1 }; trace_nodes(p)|}
    "NA";

  test "trace_nodes rejects non-pipeline"
    "trace_nodes(42)"
    {|Error(TypeError: "Function `trace_nodes` expects a Pipeline as its first argument, but got Int.")|};

  test "pipeline_print returns NA"
    {|p = pipeline { a = 1; b = a + 1 }; pipeline_print(p)|}
    "NA";

  test "pipeline_print rejects non-pipeline"
    "pipeline_print(42)"
    {|Error(TypeError: "Function `pipeline_print` expects a Pipeline, but got Int.")|};

   Printf.printf "Phase 4 — meta_flatten:\n";

  (* meta_flatten: namespaces nodes correctly *)
  let (v, _) = eval_string_env
    {|p_etl = pipeline { raw = 1; clean = raw + 1 }
p_stats = pipeline { summary_node = 2 }
meta = pipeline_of {
  etl = p_etl
  stats = p_stats
}
flat = meta_flatten(meta)
pipeline_nodes(flat)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["etl.raw", "etl.clean", "stats.summary_node"]|} then begin
    incr pass_count; Printf.printf "  ✓ meta_flatten namespaces nodes correctly\n"
  end else begin
    incr fail_count;
    let msg = Printf.sprintf "  ✗ meta_flatten nodes\n    Expected: [\"etl.raw\", \"etl.clean\", \"stats.summary_node\"]\n    Got: %s\n" result in
    failures := msg :: !failures;
    Printf.printf "%s" msg
  end;

  (* meta_flatten: automatically infers cross-pipeline dependencies *)
  let (v, _) = eval_string_env
    {|p_etl = pipeline { raw = 1; clean = raw + 1 }
p_stats = pipeline { summary_node = etl.clean + 2 }
meta = pipeline_of {
  etl = p_etl
  stats = p_stats
}
flat = meta_flatten(meta)
pipeline_deps(flat)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|{`etl.raw`: [], `etl.clean`: ["etl.raw"], `stats.summary_node`: ["etl.clean"]}|} then begin
    incr pass_count; Printf.printf "  ✓ meta_flatten infers dependencies automatically\n"
  end else begin
    incr fail_count;
    let msg = Printf.sprintf "  ✗ meta_flatten auto-deps\n    Expected: {`etl.raw`: [], `etl.clean`: [\"etl.raw\"], `stats.summary_node`: [\"etl.clean\"]}\n    Got: %s\n" result in
    failures := msg :: !failures;
    Printf.printf "%s" msg
  end;

  (* Implicit flattening: passing a MetaPipeline to pipeline_nodes/pipeline_deps *)
  let (v, _) = eval_string_env
    {|p_etl = pipeline { raw = 1; clean = raw + 1 }
p_stats = pipeline { summary_node = etl.clean + 2 }
meta = pipeline_of {
  etl = p_etl
  stats = p_stats
}
pipeline_nodes(meta)|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|["etl.raw", "etl.clean", "stats.summary_node"]|} then begin
    incr pass_count; Printf.printf "  ✓ implicit meta-pipeline flattening in built-ins works\n"
  end else begin
    incr fail_count;
    let msg = Printf.sprintf "  ✗ implicit meta-pipeline flattening\n    Expected: [\"etl.raw\", \"etl.clean\", \"stats.summary_node\"]\n    Got: %s\n" result in
    failures := msg :: !failures;
    Printf.printf "%s" msg
  end;

  (* Nested/partial dot access: meta.stats.summary_node *)
  let (v, _) = eval_string_env
    {|p_etl = pipeline { raw = 1; clean = raw + 1 }
p_stats = pipeline { summary_node = etl.clean + 2 }
meta = pipeline_of {
  etl = p_etl
  stats = p_stats
}
meta.stats.summary_node.name|}
    (Packages.init_env ()) in
  let result = Ast.Utils.value_to_string v in
  if result = {|"stats.summary_node"|} then begin
    incr pass_count; Printf.printf "  ✓ nested dot-access namespaces on meta-pipeline work\n"
  end else begin
    incr fail_count;
    let msg = Printf.sprintf "  ✗ nested dot-access on meta-pipeline\n    Expected: \"stats.summary_node\"\n    Got: %s\n" result in
    failures := msg :: !failures;
    Printf.printf "%s" msg
  end;

  Printf.printf "Phase 4 — resolve_pipeline_name:\n";

  (* Regular pipeline: name should resolve to its variable name *)
  let env_r = Packages.init_env () in
  let env_r = Test_helpers.eval_setup eval_string_env env_r "test_pipeline_ops:1024" {|my_pipe = pipeline { a = 1; b = a + 1 }|} in
  let (v_r, _) = eval_string_env
    {|my_pipe|}
    env_r in
  (match v_r with
   | Ast.VPipeline p ->
       (match Pipeline_utils.resolve_pipeline_name env_r p with
        | Some name when name = "my_pipe" ->
            incr pass_count; Printf.printf "  ✓ resolve_pipeline_name finds regular pipeline\n"
        | Some name ->
            incr fail_count;
            let msg = Printf.sprintf "  ✗ resolve_pipeline_name regular: expected \"my_pipe\", got \"%s\"\n" name in
            failures := msg :: !failures;
            Printf.printf "%s" msg
        | None ->
            incr fail_count;
            let msg = "  ✗ resolve_pipeline_name regular: returned None\n" in
            failures := msg :: !failures;
            Printf.printf "%s" msg)
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ resolve_pipeline_name regular: expected VPipeline, got %s\n" (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* Meta pipeline: name should resolve to its variable name *)
  let env_m = Packages.init_env () in
  let env_m = Test_helpers.eval_setup eval_string_env env_m "test_pipeline_ops:1053" {|p_etl = pipeline { raw = 1; clean = raw + 1 };
      p_stats = pipeline { summary_node = 2 };
      meta = pipeline_of { etl = p_etl; stats = p_stats }|} in
  let (flat_v, _) = eval_string_env
    {|meta_flatten(meta)|}
    env_m in
  (match flat_v with
   | Ast.VPipeline p ->
       (match Pipeline_utils.resolve_pipeline_name env_m p with
        | Some name when name = "meta" ->
            incr pass_count; Printf.printf "  ✓ resolve_pipeline_name finds meta pipeline\n"
        | Some name ->
            incr fail_count;
            let msg = Printf.sprintf "  ✗ resolve_pipeline_name meta: expected \"meta\", got \"%s\"\n" name in
            failures := msg :: !failures;
            Printf.printf "%s" msg
        | None ->
            incr fail_count;
            let msg = "  ✗ resolve_pipeline_name meta: returned None\n" in
            failures := msg :: !failures;
            Printf.printf "%s" msg)
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ resolve_pipeline_name meta: meta_flatten should return VPipeline, got %s\n" (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* Anonymous pipeline (never bound): should return None *)
  let env_a = Packages.init_env () in
  let (v_a, _) = eval_string_env
    {|pipeline { x = 42 }|}
    env_a in
  (match v_a with
   | Ast.VPipeline p ->
       (match Pipeline_utils.resolve_pipeline_name env_a p with
        | None ->
            incr pass_count; Printf.printf "  ✓ resolve_pipeline_name returns None for anonymous pipeline\n"
        | Some name ->
            incr fail_count;
            let msg = Printf.sprintf "  ✗ resolve_pipeline_name anonymous: expected None, got \"%s\"\n" name in
            failures := msg :: !failures;
            Printf.printf "%s" msg)
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ resolve_pipeline_name anonymous: expected VPipeline, got %s\n" (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* pipeline_report tests *)
  Printf.printf "pipeline_report:\n";

  test "pipeline_report rejects non-pipeline"
    {|pipeline_report(42)|}
    {|Error(TypeError: "[L1:C1] Function `pipeline_report` expects a Pipeline, but got Int.")|};

  let env_rep = Packages.init_env () in
  let env_rep = Test_helpers.eval_setup eval_string_env env_rep "test_pipeline_ops:1111" {|p = pipeline { a = 1; b = a + 1 }|} in

  test "pipeline_report rejects invalid target value"
    {|p = pipeline { a = 1 }; pipeline_report(p, target = "pdf")|}
    {|Error(ValueError: "Function `pipeline_report` target must be \"ssh\" or \"web\", but got \"pdf\". Use `target = \"ssh\"` for plain-text reports or `target = \"web\"` for HTML reports.")|};

  test "pipeline_report rejects invalid target type"
    {|p = pipeline { a = 1 }; pipeline_report(p, target = 42)|}
    {|Error(TypeError: "Function `pipeline_report` target must be a string: \"ssh\" or \"web\", but got Int.")|};

  let (v_rep, env_rep) = eval_string_env
    {|pipeline_report(p, file = "_pipeline/test_report.md")|}
    env_rep in
  (match v_rep with
   | Ast.VString path ->
       if path = "_pipeline/test_report.md" && Sys.file_exists path then begin
         let (v_content, _) = eval_string_env
           {|read_file("_pipeline/test_report.md")|}
           env_rep in
         match v_content with
         | Ast.VString s ->
             let has_header = String.starts_with ~prefix:"# Pipeline Report" s in
             let has_mermaid = String.contains s '`' in
             if has_header && has_mermaid then begin
               incr pass_count; Printf.printf "  ✓ pipeline_report generated report content looks correct\n"
             end else begin
               incr fail_count;
               let msg = Printf.sprintf "  ✗ pipeline_report content mismatch. Header: %b, Mermaid: %b\n" has_header has_mermaid in
               failures := msg :: !failures;
               Printf.printf "%s" msg
             end;
             (try Sys.remove path with _ -> ())
         | _ ->
             incr fail_count;
             let msg = "  ✗ pipeline_report: read_file did not return string\n" in
             failures := msg :: !failures;
             Printf.printf "%s" msg;
             (try Sys.remove path with _ -> ())
       end else begin
         incr fail_count;
         let msg = Printf.sprintf "  ✗ pipeline_report file not found or path mismatch: %s\n" path in
         failures := msg :: !failures;
         Printf.printf "%s" msg
       end
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ pipeline_report: expected VString path, got %s\n" (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  let (v_rep_web, env_rep) = eval_string_env
    {|pipeline_report(p, target = "web", file = "_pipeline/test_report.html")|}
    env_rep in
  (match v_rep_web with
   | Ast.VString path ->
       if path = "_pipeline/test_report.html" && Sys.file_exists path then begin
         let (v_content, _) = eval_string_env
           {|read_file("_pipeline/test_report.html")|}
           env_rep in
         match v_content with
         | Ast.VString s ->
             let has_doctype = String.contains s '<' && (String.starts_with ~prefix:"<!DOCTYPE html>" s || String.starts_with ~prefix:"<!doctype html>" (String.lowercase_ascii s)) in
             let has_mermaid = String.contains s 'm' && String.contains s 'e' in
             if has_doctype && has_mermaid then begin
               incr pass_count; Printf.printf "  ✓ pipeline_report generated HTML report content looks correct\n"
             end else begin
               incr fail_count;
               let msg = Printf.sprintf "  ✗ pipeline_report HTML content mismatch. Doctype: %b, Mermaid: %b\n" has_doctype has_mermaid in
               failures := msg :: !failures;
               Printf.printf "%s" msg
             end;
             (try Sys.remove path with _ -> ())
         | _ ->
             incr fail_count;
             let msg = "  ✗ pipeline_report web: read_file did not return string\n" in
             failures := msg :: !failures;
             Printf.printf "%s" msg;
             (try Sys.remove path with _ -> ())
       end else begin
         incr fail_count;
         let msg = Printf.sprintf "  ✗ pipeline_report web file not found or path mismatch: %s\n" path in
         failures := msg :: !failures;
         Printf.printf "%s" msg
       end
   | other ->
        incr fail_count;
        let msg = Printf.sprintf "  ✗ pipeline_report web: expected VString path, got %s\n" (Ast.Utils.value_to_string other) in
        failures := msg :: !failures;
        Printf.printf "%s" msg);

  print_newline ();

  Printf.printf "Phase 12 — node_when / node_fork:\n";

  (* §1: Undefined var in condition should fail immediately at pipeline construction time *)
  test "node_when: undefined var in condition fails at construction time"
    {|
      p = pipeline { flag = node_when(undefined_var == "1", rn(script = "a.R")) };
      error_code(p)
    |}
    "NameError";

  (* §2: node_fork with error condition propagates immediately *)
  test "node_fork: error condition propagates immediately"
    {|
      p = pipeline { m = node_fork(undefined_var == "1", rn(script = "a.R"), .default = rn(script = "b.R")) };
      error_code(p)
    |}
    "NameError";

  (* §3: Non-node value raises TypeError *)
  test "node_when: non-node return value raises TypeError"
    {|
      p = pipeline { x = node_when(true, 42) };
      error_code(p)
    |}
    "TypeError";

  (* node_when(true, node) includes the node — needs OCaml type matching *)
  let (v, _) = eval_string_env
    {|p = pipeline { flag = node_when(true, rn(script = "a.R")) }; pipeline_nodes(p) |> length |}
    (Packages.init_env ()) in
  (match v with
   | Ast.VInt n when n >= 1 ->
       incr pass_count; Printf.printf "  ✓ node_when(true, node) includes node\n"
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ node_when(true, node) includes node\n    Expected length >= 1\n    Got: %s\n" (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* node_when(false, node) excludes the node — needs OCaml type matching *)
  let (v, _) = eval_string_env
    {|p = pipeline { flag = node_when(false, rn(script = "a.R")) }; pipeline_nodes(p) |> length |}
    (Packages.init_env ()) in
  (match v with
   | Ast.VInt 0 ->
       incr pass_count; Printf.printf "  ✓ node_when(false, node) excludes node\n"
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ node_when(false, node) excludes node\n    Expected length 0\n    Got: %s\n" (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* node_fork: first truthy condition wins — needs OCaml type matching *)
  let (v, _) = eval_string_env
    {|p = pipeline {
        m = node_fork(
          true, rn(script = "a.R"),
          false, rn(script = "b.R"),
          .default = rn(script = "c.R")
        )
      }; pipeline_nodes(p) |> length |}
    (Packages.init_env ()) in
  (match v with
   | Ast.VInt n when n >= 1 ->
       incr pass_count; Printf.printf "  ✓ node_fork selects first truthy condition\n"
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ node_fork selects first truthy condition\n    Expected length >= 1\n    Got: %s\n" (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* node_fork: all false, no default → excluded — needs OCaml type matching *)
  let (v, _) = eval_string_env
    {|p = pipeline { m = node_fork(false, rn(script = "a.R"), false, rn(script = "b.R")) }; pipeline_nodes(p) |> length |}
    (Packages.init_env ()) in
  (match v with
   | Ast.VInt 0 ->
       incr pass_count; Printf.printf "  ✓ node_fork all false, no default excludes node\n"
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ node_fork all false, no default excludes node\n    Expected length 0\n    Got: %s\n" (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

  (* node_fork: all false, with default → included — needs OCaml type matching *)
  let (v, _) = eval_string_env
    {|p = pipeline {
        m = node_fork(
          false, rn(script = "a.R"),
          false, rn(script = "b.R"),
          .default = rn(script = "c.R")
        )
      }; pipeline_nodes(p) |> length |}
    (Packages.init_env ()) in
  (match v with
   | Ast.VInt n when n >= 1 ->
       incr pass_count; Printf.printf "  ✓ node_fork with .default includes fallback\n"
   | other ->
       incr fail_count;
       let msg = Printf.sprintf "  ✗ node_fork with .default includes fallback\n    Expected length >= 1\n    Got: %s\n" (Ast.Utils.value_to_string other) in
       failures := msg :: !failures;
       Printf.printf "%s" msg);

   print_newline ()
