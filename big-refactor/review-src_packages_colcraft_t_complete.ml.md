# Review: src/packages/colcraft/t_complete.ml

**Lines**: 273
**Severity summary**: 1 critical, 1 warning, 0 info

---

## CRITICAL: Unvalidated List.nth access

- **Line 193**: `List.nth final_combos_arr.(i) id_idx` — `List.nth` raises `Failure "nth"` if `id_idx` exceeds the list length. Although `id_idx` is computed from `find_idx id_cols 0` and should be in-bounds, this is a defensive bug — if `id_cols` or the cartesian product has an invariant mismatch, it crashes rather than returning a VError.

  **Fix**: Replace `List.nth` with `List.nth_opt` + explicit error propagation or convert the list elements to arrays for O(1) indexed access (which aligns with the surrounding code's pattern).

---

## WARNING: Function too long

- **Lines 31–272**: The anonymous function registered via `make_builtin_named` is ~242 lines long, handles argument parsing, cartesian product computation, combo-to-row mapping, and per-column reconstruction. This violates the >80 line guideline and makes the control flow hard to follow.

  **Fix**: Extract named helper functions: `parse_complete_args`, `get_unique_vals`, `get_nested_combos`, `build_complete_columns`. The `get_val` inner function (line 60) already exists as a partial extraction but the rest of the logic is a single monolithic block.
