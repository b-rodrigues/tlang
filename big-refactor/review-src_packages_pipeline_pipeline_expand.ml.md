# Review: src/packages/pipeline/pipeline_expand.ml

**Lines**: 608
**Severity summary**: 2 critical, 5 warning, 1 info

---

## CRITICAL: Hashtbl.find without guard — can raise `Not_found`

- **Line 399**: `Hashtbl.find dependents dep` in the Kahn's algorithm initialization. Although `dep` is filtered by `pattern_dep_names` to only include names in `patterned_node_names` (which are all initialized as keys), this relies on an invariant rather than a runtime check. If a programming error introduces a dependency on an uninitialized name, this panics.

  **Fix**: Replace with `Hashtbl.find_opt dependents dep` and handle `None` with an error return.

- **Line 411**: `Hashtbl.find in_degree dependent` on the dependent name dequeued from `Hashtbl.find dependents name`. The same invariant concern applies.

  **Fix**: Use `Hashtbl.find_opt in_degree dependent` and handle `None`.

- **Line 414**: `Hashtbl.find dependents name` where `name` comes from the queue. Same invariant concern.

  **Fix**: Use `Hashtbl.find_opt dependents name` and handle `None`.

## CRITICAL: List.nth without bounds check — can raise `Failure`

- **Line 499**: `List.nth branch_names (dep_index_for_branch b dep)` in `make_branch_deps`. If `dep_index_for_branch` returns an index >= `List.length branch_names`, this raises `Failure "nth"`. The index is guaranteed in-range by construction (indices are 0..branch_count-1) but there is no runtime guard.

  **Fix**: Replace with `List.nth_opt branch_names (dep_index_for_branch b dep)` and produce a `VError` if `None`.

- **Line 513**: Same construct in `make_branch_explicit_deps`.

  **Fix**: Same as above.

## WARNING: Dead code — duplicated `value_length` definition

- **Line 27**: `value_length` is defined at lines 27-32 and again at lines 203-208. The second definition shadows the first, making lines 27-32 dead code.

  **Fix**: Remove the first definition (lines 27-32).

## WARNING: Catch-all exception handler silently swallows errors

- **Line 141**: `with _ -> VNA NAGeneric` in `resolve_dep_value` wraps `Eval.eval_expr (ref env) expr` and catches all exceptions, converting them to `VNA`. This could mask genuine bugs (e.g., type errors, stack overflow) as missing values.

  **Fix**: Catch only the specific exceptions that `eval_expr` can produce (e.g., specific error types), or propagate the error instead of silently returning `VNA`.

## WARNING: Catch-all `| _ -> expr` in `substitute_vars_in_expr` silently skips constructors

- **Line 116**: The wildcard `| _ -> expr` in `substitute_vars_in_expr` silently returns the expression unchanged for unhandled node types. `Ast.expr` has constructors `Value`, `ColumnRef`, `ShellExpr`, `Block`, `PipelineDef`, `PipelineOfDef`, and `IntentDef` that are not matched. If a command expression contains these, variable substitution is silently skipped rather than raising an error.

  **Fix**: Either handle each constructor explicitly (even if just passing through) or add a comment explaining why they are intentionally excluded.

## WARNING: Catch-all `| _ -> 1` / `| _ -> v` in `value_length` and `slice_value`

- **Line 32 / 208**: `| _ -> 1` in `value_length` treats any unhandled value type as length 1. New value types (e.g., future pipeline types) would silently get length 1.
- **Line 49**: `| _ -> v` in `slice_value` returns the value unchanged for unhandled types.

  **Fix**: Add explicit cases for known value types or raise a structured error for unknown types.

## WARNING: Long function — `expand_pipeline_internal`

- **Lines 364–563**: ~200 lines with deeply nested logic (topological sort, branch generation, result assembly). The function handles multiple concerns: dependency graph construction, topological sorting, branch indexing, and pipeline field merging.

  **Fix**: Extract the Kahn's algorithm portion (lines 388–424) and the result assembly portion (lines 462–547) into named helper functions.

## INFO: `Slice_value` returns `VNA NAGeneric` for out-of-range index, not a structured error

- **Lines 39, 43, 48**: `slice_value` returns `VNA NAGeneric` when an index is out of bounds. Downstream callers may not distinguish between a genuine NA and an indexing error.

  **Fix**: Consider returning an `Error` value for invalid indices to make the distinction explicit.
