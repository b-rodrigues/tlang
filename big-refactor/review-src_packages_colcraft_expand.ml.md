# Review: src/packages/colcraft/expand.ml

**Lines**: 230
**Severity summary**: 1 critical, 0 warnings, 1 info

---

## CRITICAL: Unvalidated List.nth access

- **Line 131**: `List.nth combos_arr.(0) i` — `List.nth` raises `Failure "nth"` if the index `i` exceeds the length of the list `combos_arr.(0)`. This is guarded by `if nrows > 0` but not by a check that `i < length_of_list`. If `column_names` has more entries than any individual combo (e.g., due to an invariant mismatch), this crashes rather than returning a VError.

  **Fix**: Replace with `List.nth_opt combos_arr.(0) i` and handle the `None` case (e.g., fall back to `VNA NAGeneric`), or convert the combo lists to arrays before indexed access. Note that `expand.ml`'s own `expand_impl` at line 123 correctly uses `List.nth_opt` in the adjacent `Array.init` — this `List.nth` call on line 131 is inconsistent with the surrounding safe-access pattern.

---

## INFO: Code duplication with t_complete.ml

- **Lines 8–13**: The `cartesian` function is duplicated verbatim in `t_complete.ml` (lines 132–138). Both files also define an identical `expand_input` type and processing logic.

  **Fix**: Move `cartesian`, `expand_input` type, and shared expand/complete helpers to a common module (e.g., `colcraft/expand_common.ml`) to avoid duplication.
