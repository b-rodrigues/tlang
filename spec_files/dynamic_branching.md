# Dynamic Branching for Tlang

## Overview

Add dynamic branching to tlang's pipeline system, inspired by the `targets` R package's `pattern` argument. The feature allows a pipeline node to produce multiple branches (one per element of an upstream node) and downstream nodes to consume branches individually, all without the user manually writing each branch.

The implementation uses **metaprogramming** — an `expand_pipeline(p)` function walks the pipeline, resolves upstream data to determine branch counts, and generates either an expanded `VPipeline` value or an intermediate `.t` script with all branches materialized as explicit nodes. The Nix backend remains completely unchanged.

## Motivation

In `targets`, dynamic branching lets users write:

```r
list(
  tar_target(fixed_radius, sample.int(n = 10, size = 2)),
  tar_target(cycling_radius, sample.int(n = 10, size = 2)),
  tar_target(
    points,
    spirograph_points(fixed_radius, cycling_radius),
    pattern = map(fixed_radius, cycling_radius)
  )
)
```

Each combination of `fixed_radius` and `cycling_radius` becomes a separate branch of `points`, and referencing `points` as a whole automatically aggregates all branches.

In tlang, the equivalent should look like:

```t
p = pipeline {
  fixed_radius = sample(1:10, size = 2)
  cycling_radius = sample(1:10, size = 2)
  points = node(
    command = <{ spirograph_points(fixed_radius, cycling_radius) }>,
    pattern = map_pattern(fixed_radius, cycling_radius)
  )
}

-- Expansion step
p_expanded = expand_pipeline(p)
-- Or with intermediate script:
expand_pipeline(p, to_script = "expanded.t")

-- Build
build_pipeline(p_expanded)
```

## Architecture

```
User pipeline with patterns:
  p = pipeline {
    params = [1, 2, 3]
    results = node(compute(params), pattern = map_pattern(params))
  }

build_pipeline(p)
  ↓  (detects unexpanded patterns)
  ✖ Error: "Pipeline contains dynamic branching patterns.
     Call build_pipeline(expand_pipeline(p)) instead."

expand_pipeline(p)
  ↓  (evaluates upstream data, checks for branch name collisions)
  ↓  returns expanded VPipeline (and optionally writes .t file)
  p_expanded = pipeline {
    params = [1, 2, 3]
    results_branch_1 = node(compute(1))
    results_branch_2 = node(compute(2))
    results_branch_3 = node(compute(3))
  }

build_pipeline(expand_pipeline(p))
  ↓  (Nix works unchanged — all nodes are explicit)
  BuildLog ✓
```

## Changes

### 1. AST — `src/ast.ml`

#### New type: `pattern_expr`

```ocaml
type pattern_expr =
  | PatternMap of string list         (* map(dep1, dep2, …)             *)
  | PatternCross of pattern_expr list  (* cross(map(...), map(...), …)  *)
  | PatternSlice of string * int list  (* slice(dep, [3, 4])            *)
  | PatternHead of string * int        (* head(dep, n)                  *)
  | PatternTail of string * int        (* tail(dep, n)                  *)
  | PatternSample of string * int      (* sample(dep, n)                *)
```

#### New value: `VPattern`

```ocaml
  | VPattern of pattern_expr
```

#### New fields on `unbuilt_node`

```ocaml
and unbuilt_node = {
  …
  un_pattern : pattern_expr option;     (* None = no dynamic branching  *)
  un_iteration : string;                (* "vector" | "list"            *)
}
```

#### New fields on `pipeline_result`

Since `pipeline_result` stores node metadata across parallel assoc lists (rather than keeping raw `unbuilt_node` records), we add:

```ocaml
and pipeline_result = {
  …
  p_has_patterns : bool;                      (* true if any node has a pattern *)
  p_patterns     : (string * pattern_expr) list; (* Map node name -> pattern *)
  p_iterations   : (string * string) list;       (* Map node name -> iteration type *)
}
```

The `p_has_patterns` flag lets `build_pipeline` and `rerun_pipeline` quickly detect unexpanded patterns without scanning every list.

---

### 2. Evaluator — `src/eval.ml`

#### Handle `pattern` and `iteration` arguments in `node()` / `pyn()` / `rn()` / `jln()` / `qn()` / `shn()`

Because the `pattern` argument (e.g., `pattern = map_pattern(params)`) references upstream node names as bare symbols, **it must not be evaluated normally**. Normal evaluation would try to look up `params` as a variable in scope, resulting in a `NameError` at pipeline definition time.

Instead, the evaluator must inspect the **AST** of the `pattern` argument directly (similar to how `deps` are extracted at line 1176 in `eval.ml`):

```ocaml
(* Inside node/pyn/rn/etc. dispatch *)
let un_pattern =
  match List.assoc_opt (Some "pattern") args with
  | None -> None
  | Some pattern_expr_ast ->
      (* Inspect AST node directly without evaluation *)
      let rec parse_pattern ast =
        match ast.node with
        | Call { fn = { node = Var "map_pattern"; _ }; args } ->
            let deps = List.map (function
              | (_, { node = Var name; _ }) -> name
              | (_, { node = Value (VString name | VSymbol name); _ }) -> name
              | _ -> failwith "map_pattern expects node name symbols or strings"
            ) args in
            Some (PatternMap deps)
        | Call { fn = { node = Var "cross_pattern"; _ }; args } ->
            let sub_patterns = List.filter_map (fun (_, arg) -> parse_pattern arg) args in
            Some (PatternCross sub_patterns)
        (* Add cases for PatternSlice, PatternHead, etc. *)
        | other ->
            (* Unknown pattern form — fail immediately with a clear error *)
            Error.make_error TypeError
              (Printf.sprintf "Unsupported pattern= value: expected map_pattern(...) or cross_pattern(...), got: %s"
                 (Nix_unparse.expr_to_string (Ast.mk_expr other)))
            |> ignore;
            None
      in
      parse_pattern pattern_expr_ast
in
let un_iteration =
  match List.assoc_opt (Some "iteration") args with
  | Some { node = Value (VString iter | VSymbol iter); _ } -> iter
  | _ -> "vector" (* Default *)
in
```

> **Note**: The `_` arm should raise a proper `VError TypeError` and return it early from the node dispatch, not silently return `None`. Returning `None` would cause the pattern to be silently dropped.

Store these in the OCaml `VNode` record.

#### Handle `VPattern` and `un_iteration` in `eval_pipeline`

During desugaring of nodes in `eval_pipeline`, if a desugared node has `un_pattern = Some pattern`, set the `p_has_patterns` flag and collect them into the `p_patterns` and `p_iterations` lists on the final `pipeline_result`.

#### Pattern detection in `rerun_pipeline`

`rerun_pipeline` reconstructs `unbuilt_node` records from the parallel assoc lists. It must:
1. Populate `un_pattern` from `p_patterns` and `un_iteration` from `p_iterations` when reconstructing each node.
2. Check `prev.p_has_patterns` early (before entering the topo-sort/eval loop) and return a `StructuralError`:

```ocaml
and rerun_pipeline ?(strict=false) ?(verbose=true) env_ref (prev : Ast.pipeline_result) : value =
  if prev.p_has_patterns then
    Error.make_error StructuralError
      "Pipeline contains unexpanded dynamic branching patterns. \
       Use expand_pipeline(p) to resolve branches before building. \
       See help(expand_pipeline) for details."
  else
    (* existing reconstruction + topo-sort logic … *)
```

#### Guard ordering in `build_pipeline`

`build_pipeline` calls `rerun_pipeline` internally (line 129 of `build_pipeline.ml`). To give the user the clearest error message, the `p_has_patterns` check should happen **first**, at the top of `build_fn`, before `rerun_pipeline` is called:

```ocaml
| (_, VPipeline p) ->
    if p.p_has_patterns then
      Error.make_error StructuralError "Pipeline contains unexpanded …"
    else
      (* existing: call rerun_pipeline, then Builder.populate_pipeline … *)
```

The check in `rerun_pipeline` is then defense-in-depth (guards against internal callers that bypass `build_pipeline`).

---

### 3. Serialization — `src/serialization.ml`

Update the serializers and deserializers for `pipeline_result` to correctly preserve the new fields:
- `p_has_patterns`
- `p_patterns`
- `p_iterations`

This ensures that caching, writing pipeline states to files, and IPC/FFI calls properly preserve pattern metadata.

---

### 4. Pattern functions — `src/packages/core/t_pattern.ml` (NEW)

New file registering the pattern descriptor functions. Standardize builtin signatures using `make_builtin` or `make_builtin_named`.

Because `map_pattern` and `cross_pattern` are processed via **AST inspection** at the call site in the node dispatch (not via normal function evaluation), the registered builtins exist primarily for documentation and reflection. They should **not** be callable at runtime and must error clearly if called outside of a `pattern=` argument:

```ocaml
(* src/packages/core/t_pattern.ml *)

open Ast

let map_pattern_fn _args _env =
  (* Not callable at runtime — processed by AST inspection in eval.ml's node dispatch *)
  Error.make_error TypeError
    "map_pattern() can only be used as the value of pattern= inside a node() call."

let cross_pattern_fn _args _env =
  Error.make_error TypeError
    "cross_pattern() can only be used as the value of pattern= inside a node() call."
```

Register via `T_pattern.register env` in `src/packages/core/packages.ml` alongside other core registrations.

> **Note**: Do NOT add `map_pattern` or `cross_pattern` to `known_symbols`. That list registers bare words as `VSymbol` values (for keyword-style args like `runtime = R`). These are functions, registered as `VBuiltin` — adding them to `known_symbols` would shadow the function bindings and break calls.

---

### 5. Pipeline expansion — `src/packages/pipeline/pipeline_expand.ml` (NEW)

The core of the feature. This function:

1. Takes a `VPipeline` value (that may contain pattern nodes)
2. Evaluates upstream dependency values (from in-memory cache or built artifacts)
3. Determines branch counts from upstream data shapes
4. Checks for **branch naming collisions** (e.g. if `results_branch_1` already exists as a user-defined node)
5. Generates explicit nodes for each branch
6. Returns a new `VPipeline` with all branches as regular nodes
7. Optionally writes a `.t` script representing the expanded pipeline

#### Expansion logic details

```
For each node (name, un) in the pipeline:

  If un.un_pattern = None:
    → Keep node as-is.
  
  If un.un_pattern = Some (PatternMap dep_names):
    1. For each dep_name in dep_names:
       a. Look up the dependency's value from in-memory cache, environment, or built artifact.
       b. Determine the value's length (VList, VVector, VDataFrame, etc.).
       c. If any dep is unavailable → error with suggestion.
    2. Validate that all deps have the same length (like targets' map() semantics).
       If lengths differ → error: "map_pattern deps must all have equal lengths. Got N1 for 'a', N2 for 'b'."
    3. branch_count = common length.
    4. For i = 1 .. branch_count:
       a. branch_name = name ^ "_branch_" ^ string_of_int i
       b. Check if branch_name already exists in pipeline → raise NameError on collision.
       c. Slice each dependency at index i-1.
       d. Create a new node expression with the sliced values inlined as literals.
    5. Return the list of branch nodes.
```

#### Branch command parameterization & AST Unparsing

To generate the expanded `.t` script when `to_script` is requested, we need a way to turn OCaml AST expressions back into tlang code. We should reuse or extend the AST unparsing logic (e.g., exposing `Nix_unparse.expr_to_string` or a dedicated OCaml expression unparser).

---

### 6. Error propagation / guards in building and composition

#### Build/Populate Guards
In `build_pipeline.ml`'s `build_fn`, and in `populate_pipeline.ml`, raise a `StructuralError` if `p_has_patterns` is true.

#### Composition Guards
In `pipeline_composition.ml` (specifically inside functions that manipulate pipeline results like `chain`, `parallel`, `patch`), verify that none of the inputs have `p_has_patterns = true`. If they do, fail early with a `StructuralError`.

---

### 7. Aggregation and branch access

After expansion, all branch access is through the regular pipeline API:
- `read_node(p_expanded.results_branch_1)` — normal node reading
- `p_expanded.results_branch_1` — normal dot access
- `pipeline_nodes(p_expanded)` — shows all branch names

For v1, auto-aggregation is not implemented; users explicitly reference individual branches.

---

## Files to modify / create

| File | Action | Description |
|------|--------|-------------|
| `src/ast.ml` | Modify | Add `pattern_expr` type, `VPattern` value, `un_pattern`/`un_iteration` fields, `p_has_patterns`/`p_patterns`/`p_iterations` fields to `pipeline_result` |
| `src/eval.ml` | Modify | Parse `pattern` and `iteration` AST args in node dispatch; store patterns in parallel lists in `eval_pipeline`; check in `rerun_pipeline` |
| `src/serialization.ml` | Modify | Add serialization/deserialization logic for the new pattern/iteration lists |
| `src/packages/core/packages.ml` | Modify | Register `T_pattern`; add pattern names to `known_symbols` |
| `src/packages/core/t_pattern.ml` | **New** | Register Builtins `map_pattern`, `cross_pattern`, etc. |
| `src/packages/pipeline/pipeline_expand.ml` | **New** | Core `expand_pipeline` function (with collision checks and value evaluation) |
| `src/packages/pipeline/pipeline_composition.ml` | Modify | Guard functions (`chain`, `parallel`, `patch`) against pattern pipelines |
| `src/packages/pipeline/build_pipeline.ml` | Modify | Guard against unexpanded patterns before building |
| `src/packages/pipeline/populate_pipeline.ml` | Modify | Guard against unexpanded patterns before populating |
| `tests/test_pipeline_ops.ml` | Modify | New test phase for dynamic branching |
| `tests/golden/t_scripts/` | Add | Golden test T scripts |
| `docs/api-reference.md` | Modify | Document `map_pattern`, `cross_pattern`, `expand_pipeline` |
| `summary.md` | Modify | Add feature entry |
| `examples/` | Add | Usage example |

## Example user workflow

```t
-- 1. Define pipeline with dynamic branches
p = pipeline {
  params = [10, 20, 30]
  results = node(
    command = <{ compute(params) }>,
    pattern = map_pattern(params)
  )
}

-- 2. Calling build_pipeline directly fails with helpful error:
--    build_pipeline(p)
--    ✖ Error(StructuralError: "Pipeline contains unexpanded dynamic
--      branching patterns. Use expand_pipeline(p) to resolve branches
--      before building. See help(expand_pipeline) for details.")

-- 3. Expand and build (inline):
p_expanded = expand_pipeline(p)
build_pipeline(p_expanded)

-- 4. Expand with intermediate script for inspection:
expand_pipeline(p, to_script = "expanded_pipeline.t")
-- writes expanded_pipeline.t:
--   p_expanded = pipeline {
--     params = [10, 20, 30]
--     results_branch_1 = node(command = <{ compute(10) }>)
--     results_branch_2 = node(command = <{ compute(20) }>)
--     results_branch_3 = node(command = <{ compute(30) }>)
--   }

-- 5. Cross pattern example (cartesian product):
p2 = pipeline {
  radii = [1, 2]
  cycles = [3, 4]
  spiro = node(
    command = <{ spirograph(radii, cycles) }>,
    pattern = cross_pattern(map_pattern(radii), map_pattern(cycles))
  )
}

p2_expanded = expand_pipeline(p2)
build_pipeline(p2_expanded)
-- Results in 4 branches: spiro_branch_1 .. spiro_branch_4
-- (1,3), (1,4), (2,3), (2,4)
```

## Open questions for later iterations

1. **Auto-aggregation**: Should referencing a previously-branched node name (without `_branch_N` suffix) auto-combine all branches?
2. **DataFrame row branching**: For `iteration = "group"`, branching over row groups of a grouped DataFrame (like `tar_group()` in targets).
3. **Batching**: `tar_rep`-style batching where each branch handles multiple iterations for performance.
4. **Cross-language branching**: Resolving branch counts from upstream foreign-language nodes by reading their build artifacts.
