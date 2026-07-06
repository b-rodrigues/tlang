# Verification: src/packages/pipeline/pipeline_expand.ml

## File: src/packages/pipeline/pipeline_expand.ml

### Finding: CRITICAL — Hashtbl.find without guard (Original lines: 399, 411, 414)
**Actual line**: 399, 411, 414
**Status**: CONFIRMED
**Evidence**:
- Line 399: `Hashtbl.replace dependents dep (name :: Hashtbl.find dependents dep)` — in Kahn's algorithm initialization, `dep` is filtered by `pattern_dep_names` to only include names in `patterned_node_names`, all of which are initialized as keys on line 391-393. But `Hashtbl.find` could raise `Not_found` if the invariant is broken.
- Line 411: `let new_deg = Hashtbl.find in_degree dependent - 1 in` — `dependent` comes from `Hashtbl.find dependents name`, same invariant concern.
- Line 414: `(Hashtbl.find dependents name)` — where `name` comes from the queue, same concern.
**Verdict**: All three uses rely on invariants that should hold given the initialization on lines 391-401, but `Hashtbl.find` without a guard is fragile.
**Better fix**: Use `Hashtbl.find_opt` and handle `None` with an error return.

---

### Finding: CRITICAL — List.nth without bounds check (Original lines: 499, 513)
**Actual line**: 499, 513
**Status**: CONFIRMED
**Evidence**:
- Line 499: `List.nth branch_names (dep_index_for_branch b dep)` — `dep_index_for_branch` returns an index from `branch_dep_indices` which is constructed from `0..branch_count-1`.
- Line 513: Same pattern with `List.nth branch_names (dep_index_for_branch b dep)`.
The index is guaranteed in-range by construction, but there's no runtime guard.
**Verdict**: Safe under current invariants but could cause `Failure "nth"` if invariants are broken by a future refactor.
**Better fix**: Replace with `List.nth_opt` and produce a `VError` if `None`.

---

### Finding: Dead code — duplicated `value_length` definition (Original line: 27 and 203-208)
**Actual line**: 27-32 and 203-208
**Status**: CONFIRMED
**Evidence**:
- Lines 27-32: First `value_length` definition
- Lines 203-208: Second `value_length` definition, identical to the first
The second definition at line 203 shadows the first, making lines 27-32 dead code.
**Verdict**: Clear dead code — identical duplicate. The shadowing is harmless (both definitions are the same) but wastes lines and is confusing.
**Better fix**: Remove the first definition (lines 27-32).

---

### Finding: Catch-all exception handler silently swallows errors (Original line: 141)
**Actual line**: 141
**Status**: CONFIRMED
**Evidence**: `with _ -> VNA NAGeneric` wraps `Eval.eval_expr (ref env) expr` and catches ALL exceptions. This could mask genuine bugs (type errors, stack overflow, etc.) by converting them to `VNA`.
**Verdict**: This is overly broad. Catching all exceptions and silently converting to `VNA` hides potentially serious issues.
**Better fix**: Catch only specific exceptions that `eval_expr` can produce, or propagate the error instead of silently returning `VNA`.

---

### Finding: Catch-all `| _ -> expr` in `substitute_vars_in_expr` silently skips constructors (Original line: 116)
**Actual line**: 116
**Status**: CONFIRMED
**Evidence**: `| _ -> expr` — the wildcard silently returns the expression unchanged for unhandled `Ast.expr` node types. Several constructors like `Value`, `ColumnRef`, `ShellExpr`, `Block`, `PipelineDef`, `PipelineOfDef`, and `IntentDef` are not explicitly matched.
**Verdict**: Some of these types (like `Value`) are handled elsewhere, but the catch-all means new constructors won't trigger compiler warnings.
**Better fix**: Handle each constructor explicitly or add a comment documenting intentional exclusion.

---

### Finding: Catch-all `| _ -> 1` / `| _ -> v` in `value_length` and `slice_value` (Original lines: 32/208, 49)
**Actual line**: 32, 49, 208
**Status**: CONFIRMED
**Evidence**:
- Line 32/208: `| _ -> 1` — treats any unhandled value type as length 1.
- Line 49: `| _ -> v` — returns the value unchanged for unhandled types.
**Verdict**: These catch-alls could silently produce incorrect results for future value types. Explicit handling would catch new types at compile time.
**Better fix**: Add explicit cases for known value types or raise a structured error for unknown types.

---

### Finding: Long function — `expand_pipeline_internal` (Original line: 364-563)
**Actual line**: 364-563
**Status**: CONFIRMED
**Evidence**: ~200 lines containing topological sort (Kahn's algorithm), branch generation, result assembly, and file writing logic.
**Verdict**: The function handles multiple concerns and is hard to follow as a monolithic block. At ~200 lines it well exceeds the 80-line guideline.
**Better fix**: Extract the Kahn's algorithm portion (lines 388-424) and the result assembly portion (lines 462-547) into named helper functions.

---

### Finding: `slice_value` returns `VNA NAGeneric` for out-of-range index (Original lines: 39, 43, 48)
**Actual line**: 39, 43, 48
**Status**: CONFIRMED
**Evidence**: `slice_value` returns `VNA NAGeneric` when an index is out of bounds for List, Vector, or DataFrame values. This means callers cannot distinguish between a missing value in the data and an indexing error.
**Verdict**: Valid design concern. Returning `VNA NAGeneric` conflates two different situations (genuine NA vs indexing error).
**Better fix**: Consider returning an `Error` value for invalid indices to make the distinction explicit.
