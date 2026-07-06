# Verification: review-src_packages_colcraft_t_complete.ml.md → src/packages/colcraft/t_complete.ml

## File: src/packages/colcraft/t_complete.ml
### Finding: Unvalidated List.nth access (Original line: 193)
**Actual line**: 193 (`List.nth final_combos_arr.(i) id_idx`)
**Status**: CONFIRMED
**Evidence**: `List.nth` raises `Failure "nth"` if `id_idx >= List.length final_combos_arr.(i)`. `id_idx` is derived from `find_idx id_cols 0` (lines 181-182) where `id_cols` is the flattened list of expand input names. The `find_idx` function returns the index of `col_name` within `id_cols`. If `col_name` is in `id_cols`, `find_idx` returns a valid index `< List.length id_cols`. For id-column combos, each combo has exactly `List.length id_cols` elements. So `id_idx` should always be in bounds, but there's no explicit assertion.
**Verdict**: The review correctly identifies a defensive programming gap. While the invariant holds under current code, future changes could introduce a mismatch. The surrounding `expand.ml` code at line 123 uses `List.nth_opt` for the same operation, making this `List.nth` inconsistent with the sibling file.
**Better fix**: Replace with `List.nth_opt ...` and handle `None`, or convert combo lists to arrays for O(1) checked access (consistent with `final_combos_arr`).

---

## File: src/packages/colcraft/t_complete.ml
### Finding: Function too long (Original lines: 31-272)
**Actual line**: 31-272
**Status**: CONFIRMED
**Evidence**: The anonymous function registered via `make_builtin_named` is ~242 lines and handles argument parsing, cartesian product computation, combo-to-row mapping, and per-column reconstruction — all in a single monolith. The `get_val` inner function (line 60) is the only sub-extraction.
**Verdict**: This is a maintainability concern. The length makes the function difficult to test, review, and modify. Extracting helper functions would improve clarity and reusability.
**Better fix**: Extract `parse_complete_args`, `get_unique_vals`, `get_nested_combos`, `build_complete_columns` each into their own named functions.
