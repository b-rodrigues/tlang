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
  ↓  (evaluates upstream data, generates intermediate script)
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

#### New field on `pipeline_result`

```ocaml
and pipeline_result = {
  …
  p_has_patterns : bool;                (* true if any node has a pattern *)
}
```

This flag lets `build_pipeline` and `rerun_pipeline` quickly detect unexpanded patterns without scanning every node.

### 2. Evaluator — `src/eval.ml`

#### Handle `pattern` argument in `node()` / `pyn()` / `rn()` / `jln()` / `qn()` / `shn()`

In the special-case dispatch for node functions (around line 1094), add extraction of a `pattern` named argument:

```ocaml
let pattern_val = lookup_arg "pattern" in
let un_pattern = match pattern_val with
  | VPattern p -> Some p
  | VNA _ | VNullNode -> None
  | _ -> (* error: expected a pattern value *)
in
let un_iteration = match lookup_arg "iteration" with
  | VString "list" -> "list"
  | _ -> "vector"   (* default *)
in
```

Store these in the `VNode` record.

#### Handle `VPattern` in `eval_pipeline`

In `eval_pipeline`, during desugaring of nodes (around line 1673), if the desugared node has `un_pattern = Some pattern`, set the `p_has_patterns` flag on the pipeline result:

```ocaml
(* Inside eval_pipeline, near the result construction *)
let has_patterns = List.exists (fun (_, un) -> un.un_pattern <> None) desugared_nodes in
…
let result = VPipeline {
  …
  p_has_patterns = has_patterns;
} in
```

#### Pattern detection in `rerun_pipeline`

In `rerun_pipeline` (around line 1941), check for patterns and emit an error:

```ocaml
if prev.p_has_patterns then
  Error.make_error StructuralError
    "Pipeline contains unexpanded dynamic branching patterns. \
     Use expand_pipeline(p) to resolve branches before building. \
     See help(expand_pipeline) for details."
```

### 3. Pattern functions — `src/packages/core/t_pattern.ml` (NEW)

New file with pattern descriptor functions:

```ocaml
(* src/packages/core/t_pattern.ml *)

open Ast

(*
--# Dynamic Map Pattern
--#
--# Creates a map pattern over one or more upstream pipeline nodes.
--# Each branch corresponds to one element tuple from the dependencies.
--# Only meaningful as the value of the `pattern` argument in node().
--#
--# @name map_pattern
--# @param ... :: Node One or more upstream node names to iterate over.
--# @return :: Pattern A pattern descriptor for pipeline expansion.
--# @example
--#   node(command = ..., pattern = map_pattern(fixed_radius, cycling_radius))
--# @family pipeline
--# @export
*)
let map_pattern_fn args _env =
  match args with
  | [] -> Error.arity_error_named "map_pattern" 1 (List.length args)
  | _ ->
      let names = List.filter_map (function
        | VSymbol s -> Some s
        | VString s -> Some s
        | _ -> None
      ) args in
      if List.length names <> List.length args then
        Error.type_error "map_pattern expects node name symbols or strings as arguments."
      else
        VPattern (PatternMap names)

(*
--# Dynamic Cross Pattern
--#
--# Creates a cross pattern: one branch per combination of elements
--# from the given sub-patterns. Each sub-pattern should be a map_pattern(...)
--# or another cross_pattern(...).
--# Only meaningful as the value of the `pattern` argument in node().
--#
--# @name cross_pattern
--# @param ... :: Pattern Sub-patterns to cross.
--# @return :: Pattern A pattern descriptor for pipeline expansion.
--# @example
--#   node(command = ..., pattern = cross_pattern(
--#     map_pattern(fixed_radius),
--#     map_pattern(cycling_radius)
--#   ))
--# @family pipeline
--# @export
*)
let cross_pattern_fn (named_args : (string option * Ast.value) list) _env =
  let patterns = List.filter_map (function
    | (None, VPattern p) -> Some p
    | _ -> None
  ) named_args in
  if patterns = [] then
    Error.type_error "cross_pattern expects at least one pattern argument."
  else
    VPattern (PatternCross patterns)
```

Register in `src/packages/core/packages.ml`:

```ocaml
let env = T_pattern.register env in
  (* alongside other core registrations *)
```

And add `"map_pattern"` and `"cross_pattern"` to the `known_symbols` list.

### 4. Pipeline expansion — `src/packages/pipeline/pipeline_expand.ml` (NEW)

The core of the feature. This function:

1. Takes a `VPipeline` value (that may contain pattern nodes)
2. Evaluates upstream dependency values (from in-memory cache or built artifacts)
3. Determines branch counts from upstream data shapes
4. Generates explicit nodes for each branch
5. Returns a new `VPipeline` with all branches as regular nodes
6. Optionally writes a `.t` script representing the expanded pipeline

```ocaml
(*
--# Expand Pipeline Branches
--#
--# Resolves dynamic branching patterns in a pipeline, producing a new
--# pipeline with all branches as explicit nodes. Upstream data is
--# evaluated (from the in-memory cache or built artifacts) to determine
--# branch counts and parameterize each branch's command.
--#
--# If a pattern refers to upstream data that is not yet available
--# (e.g., an unbuilt foreign-language node), an error is raised
--# suggesting the user build upstream nodes first.
--#
--# @name expand_pipeline
--# @param p :: Pipeline The pipeline with potential dynamic patterns.
--# @param to_script :: String (Optional) If provided, writes the expanded
--#   pipeline as a T script to this file path.
--# @return :: Pipeline The expanded pipeline with all branches as explicit nodes.
--# @example
--#   p_expanded = expand_pipeline(p)
--#   build_pipeline(p_expanded)
--# @family pipeline
--# @export
*)
let expand_pipeline_fn (named_args : (string option * Ast.value) list) env =
  …
```

#### Expansion logic details

```
For each node (name, un) in the pipeline:

  If un.un_pattern = None:
    → Keep node as-is.
  
  If un.un_pattern = Some (PatternMap dep_names):
    1. For each dep_name in dep_names:
       a. Look up the dependency's value from:
          - In-memory cache (VNodeResult in pipeline_result)
          - Or the outer environment (Env)
          - Or built artifact (VComputedNode with cn_path)
       b. Determine the value's length:
          - VList items → length
          - VVector arr → Array.length
          - VDataFrame → num_rows
          - VInt/VFloat/VBool/VString → 1 (scalar)
       c. If any dep is unavailable → error with suggestion
    2. branch_count = max length across all deps
       (or the common length if they must match; map semantics)
    3. For i = 1 .. branch_count:
       a. branch_name = name ^ "_branch_" ^ string_of_int i
       b. Slice each dependency at index i-1 to get a scalar/slice
       c. Create a new node expression with the sliced values inlined
          as literal values in the command
       d. This may involve AST manipulation: replacing Var references
          to the dependency with Value literals
    4. Return the list of branch nodes.

  If un.un_pattern = Some (PatternCross patterns):
    1. Recursively resolve each sub-pattern to get its branches
    2. Compute the cartesian product of all sub-branch lists
    3. For each combination, create a branch node
    4. Name pattern: name ^ "_branch_1", name ^ "_branch_2", …
```

#### Branch command parameterization

The tricky part: when we have a node command like `<{ compute(params) }>`, and `params` is a list `[1, 2, 3]`, we need to generate branches where the command is `<{ compute(1) }>`, `<{ compute(2) }>`, `<{ compute(3) }>`.

This requires AST-level substitution: replacing `Var "params"` nodes in the command expression with `Value (VInt 1)` (or the appropriate literal).

For simple variable references (the common case), this is straightforward. For more complex expressions like `compute(params[1])`, the substitution is more involved. The initial implementation should handle:
- Direct variable references: `<{ f(x) }>` → branch has `<{ f(literal) }>`
- Dot access: `<{ f(x.field) }>` → branch has `<{ f(dataframe_row.field) }>`

Complex expression rewriting can be added in later iterations.

#### Intermediate script generation

When `to_script` is provided:

```ocaml
let script_content = "p_expanded = pipeline {\n" ^
  String.concat ";\n" (List.map (fun (name, expr) ->
    "  " ^ name ^ " = " ^ Ast.Utils.unparse_expr expr
  ) expanded_nodes) ^
  "\n}"
in
write_file to_script script_content
```

This lets users inspect, edit, or version-control the expanded pipeline.

### 5. Error propagation — `src/packages/pipeline/build_pipeline.ml`

In `build_pipeline`'s `build_fn`, before calling `rerun_pipeline`, check for patterns:

```ocaml
| (_, VPipeline p) ->
    if p.p_has_patterns then
      Error.make_error StructuralError
        "Pipeline contains unexpanded dynamic branching patterns. \
         Use expand_pipeline(p) to resolve branches before building. \
         See help(expand_pipeline) for details."
    else
      (* existing build logic *)
```

Same check in `populate_pipeline` (`src/packages/pipeline/populate_pipeline.ml`).

### 6. Aggregation and branch access — after expansion

After expansion, all branch access is through the regular pipeline API:

- `read_node(p_expanded.results_branch_1)` — normal node reading
- `p_expanded.results_branch_1` — normal dot access
- `pipeline_nodes(p_expanded)` — shows all branch names

A future `combine_branches(p, prefix, iteration = "vector")` function can aggregate branches:

```ocaml
(* Future: combine branches into a single result *)
combine_branches(p, "results", iteration = "vector")
  → combines results_branch_1, results_branch_2, …
    by row-binding (vector iteration) or wrapping in a list (list iteration)
```

For v1, auto-aggregation is not implemented; users explicitly reference individual branches.

### 7. Pipeline result integration

The `expand_pipeline` function also updates `p_exprs` (expressions), `p_deps` (dependencies), etc. for the new branch nodes:

```
Original deps:
  points → fixed_radius, cycling_radius

Expanded deps:
  points_branch_1 → fixed_radius, cycling_radius
  points_branch_2 → fixed_radius, cycling_radius
  …
```

The upstream nodes (`fixed_radius`, `cycling_radius`) are kept as-is. Their values are already evaluated and available.

## Files to modify / create

| File | Action | Description |
|------|--------|-------------|
| `src/ast.ml` | Modify | Add `pattern_expr` type, `VPattern` value, `un_pattern`/`un_iteration` fields, `p_has_patterns` field |
| `src/eval.ml` | Modify | Handle `pattern` arg in node dispatch; store pattern in `VNode`; set `p_has_patterns` in eval_pipeline; check in rerun_pipeline |
| `src/packages/core/packages.ml` | Modify | Register `T_pattern`; add to `known_symbols` |
| `src/packages/core/t_pattern.ml` | **New** | `map_pattern`, `cross_pattern`, `slice_pattern`, `head_pattern`, `tail_pattern`, `sample_pattern` |
| `src/packages/pipeline/pipeline_expand.ml` | **New** | `expand_pipeline` function — core expansion logic |
| `src/packages/pipeline/build_pipeline.ml` | Modify | Pattern detection → error with suggestion |
| `src/packages/pipeline/populate_pipeline.ml` | Modify | Pattern detection → error with suggestion |
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

-- 5. Cross pattern example:
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

1. **Auto-aggregation**: Should referencing a previously-branched node name (without `_branch_N` suffix) auto-combine all branches? This is how targets works, but requires naming convention awareness in the evaluator.

2. **DataFrame row branching**: For `iteration = "group"`, branching over row groups of a grouped DataFrame (like `tar_group()` in targets). This is more complex but powerful for data analysis pipelines.

3. **Batching**: `tar_rep`-style batching where each branch handles multiple iterations for performance.

4. **Cross-language branching**: Resolving branch counts from upstream foreign-language nodes by reading their build artifacts.
