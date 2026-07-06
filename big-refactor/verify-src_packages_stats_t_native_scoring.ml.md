# Verification: src/packages/stats/t_native_scoring.ml

## File: src/packages/stats/t_native_scoring.ml

### Finding: CRITICAL — Hashtbl.find without guard (Original lines: 342, 368)
**Actual line**: 342, 368
**Status**: CONFIRMED
**Evidence**:
- Line 342: `(match Hashtbl.find evals field row_idx with` — in `eval_predicate`, no `find_opt` guard.
- Line 368: `(match Hashtbl.find evals field row_idx with` — same pattern, no guard.

The function receives `field` from predicate structures parsed from tree models. The `evals` table is populated by `add_evals` which iterates over `fields` (extracted from tree predicates via `node_fields`). The `add_evals` function at line 438-443 validates that all field names resolve before populating the table. So the invariant is enforced at construction time.
**Verdict**: The invariant is strong (all fields are added by `add_evals` before `eval_predicate` is called), but `Hashtbl.find` could still panic if the invariant is broken by a refactoring. The fix is straightforward and low-risk.
**Better fix**: Replace with `Hashtbl.find_opt` and handle `None`.

---

### Finding: CRITICAL — Float equality (`=`) on floats in predicate evaluation (Original lines: 348, 353)
**Actual line**: 348, 353
**Status**: CONFIRMED
**Evidence**:
- Line 348 (line 353 in reviewed output): `| "equal" -> Some (f = f_val)`
- Line 353 (line 358 in reviewed output): `| "notEqual" -> Some (f <> f_val)`
Uses polymorphic equality (`=`) on floats. For tree model scoring:
1. `NaN = NaN` is `false` — could miss matches for NaN-containing predictions.
2. `0.0 = -0.0` is `true` — unlikely to cause real issues.
3. Floating-point from different backends may have precision differences.
**Verdict**: Using polymorphic equality on floats is fragile. For a tree model scoring system where threshold comparisons matter, this could cause incorrect predictions at boundary values.
**Better fix**: Use `Float.equal` for equality and `not (Float.equal ...)` for inequality, or use epsilon-based comparison.

---

### Finding: WARNING — Logic error: identical branches in else/else if (Original line: 641-644)
**Actual line**: 641-644
**Status**: CONFIRMED
**Evidence**:
```ocaml
else if List.length scores = 1 then
  out.(i) <- score_to_class ensemble.classes scores
else
  out.(i) <- score_to_class ensemble.classes scores
```
Both branches execute exactly the same code. The `else if` serves no purpose.
**Verdict**: This is either dead code (the `else if` branch is redundant and can be removed), or it was meant to handle the `List.length scores = 1` case differently (bug). Since the code is functionally identical, removing the `else if` is safe.
**Better fix**: Remove the redundant `else if` branch — keep only the `else` branch.

---

### Finding: WARNING — Function too long — predict_linear_model (Original line: 741-885)
**Actual line**: 741-885
**Status**: CONFIRMED
**Evidence**: `predict_linear_model` is ~144 lines containing three logical phases: (1) coefficient extraction (lines 742-766), (2) term resolution via `resolve_part` and `resolve_term` (lines 776-831), and (3) link function application (lines 852-884).
**Verdict**: The function is well-structured with clear logical sections, but at 144 lines it exceeds the 80-line guideline.
**Better fix**: Extract `resolve_part`, `resolve_term`, and the link-inverse application into named helpers.

---

### Finding: WARNING — Internal error propagation with raw strings (Original lines: 90-115, 121-165, 171-213)
**Actual line**: 90-115, 121-165, 171-213
**Status**: CONFIRMED
**Evidence**: Internal helpers like `get_string_field` (line 90), `get_dict_field` (line 111), `predicate_of_value` (line 121), `node_of_value` (line 171), `tree_of_value` (line 204) return `(_, string) Result.t` where the error value is a raw `string`. Callers like `predict_tree_model` (line 428) convert these with `Error.make_error TypeError msg`.
**Verdict**: This adds an unnecessary error-conversion layer. The raw string errors are only validated at runtime. Converting to structured `VError` types directly would be cleaner and more type-safe.
**Better fix**: Change internal helpers to return `(_, value) Result.t` using `Error.type_error` directly.

---

### Finding: WARNING — Float equality on float_of_string_opt comparison (Original line: 376)
**Actual line**: 376
**Status**: CONFIRMED
**Evidence**: `let s = string_of_float f in let found = List.mem s values in` — converts float to string and checks set membership via string comparison. `string_of_float` can produce different representations across platforms (e.g., `1.0` vs `"1."` vs `"1.000000"`).
**Verdict**: String comparison of float representations is fragile. Different OCaml versions or architectures could produce different string representations for the same float value.
**Better fix**: Parse `values` to floats and compare numerically.

---

### Finding: INFO — Unused `open Ast` is necessary (Original line: 2)
**Actual line**: 2
**Status**: FALSE_POSITIVE — review marked as INFO, and correctly notes it's necessary
**Evidence**: `open Ast` at line 2 is required for all the `VList`, `VDict`, `VString`, etc. variants used throughout. The review itself says "Not an issue."
**Verdict**: Not a finding to fix.
**Better fix**: None needed.
