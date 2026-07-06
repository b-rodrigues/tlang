# Verification: review-src_packages_stats_lm.ml.md → src/packages/stats/lm.ml

## File: src/packages/stats/lm.ml
### Finding: Unvalidated List.map2 on potentially-mismatched arrays (Original line: 86)
**Actual line**: 86-88 (`List.map2 ... result.term_names (Array.to_list result.coefficients)`)
**Status**: CONFIRMED
**Evidence**: `List.map2` raises `Invalid_argument` if `result.term_names` and `result.coefficients` have different lengths. No defensive length check exists before this call.
**Verdict**: The `Arrow_owl_bridge.lm_result` type should produce consistent arrays, but there is no runtime guard. A length mismatch would crash the evaluator rather than return a `VError`.
**Better fix**: Add `assert (List.length result.term_names = Array.length result.coefficients)` or a proper length check before `List.map2`.

---

## File: src/packages/stats/lm.ml
### Finding: Unvalidated List.map2 on potentially-mismatched arrays (Original line: 92)
**Actual line**: 92-94 (`List.map2 ... result.term_names (Array.to_list result.std_errors)`)
**Status**: CONFIRMED
**Evidence**: Same pattern as line 86 — `List.map2` on `result.term_names` and `result.std_errors` with no length guard.
**Verdict**: Identical risk. Should guard as well.
**Better fix**: Same as above.

---

## File: src/packages/stats/lm.ml
### Finding: Float equality checks (Original line: 185)
**Actual line**: 185 (`Array.for_all (fun w -> w = 0.0) ws`)
**Status**: CONFIRMED
**Evidence**: Uses polymorphic `=` on floats, which is an anti-pattern per AGENTS.md. `-0.0 = 0.0` is true but `Float.equal (-0.0) 0.0` is false, revealing a semantic mismatch. Also, very small floating-point values that should logically be zero won't match.
**Verdict**: Should use `Float.equal w 0.0` or an epsilon-based comparison.
**Better fix**: `Array.for_all (fun w -> Float.equal w 0.0) ws` or `Array.for_all (fun w -> Float.abs w < 1e-15) ws`.

---

## File: src/packages/stats/lm.ml
### Finding: Duplicate function name in stats_package (Original line: 140)
**Actual line**: 140 (`| VInt n -> result.(i) <- float_of_int v; loop (i + 1)`)
**Status**: FALSE_POSITIVE
**Evidence**: The review claims `"add_diagnostics"` appears twice in `stats_package` at line 140 of `lm.ml`, but `lm.ml` does not contain a `stats_package` function list. The review itself says the fix should be applied to `src/packages/core/packages.ml` line 140 — this finding belongs in a different file's review.
**Verdict**: The finding is about `src/packages/core/packages.ml`, not `src/packages/stats/lm.ml`. No such issue exists at line 140 of `lm.ml`.

---

## File: src/packages/stats/lm.ml
### Finding: Row iteration with ref accumulator for NA detection (Original lines: 128-141, 142-157)
**Actual line**: 128-157
**Status**: CONFIRMED (INFO)
**Evidence**: `float_array_of_numeric_column` uses a recursive inner loop with a mutable array accumulator. The NA check requires early exit, which is harder with pure functional folds.
**Verdict**: Review correctly notes this is acceptable per AGENTS.md rules on mutable state. No action needed.
