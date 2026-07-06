# Review: src/packages/colcraft/pivot_wider.ml

**Lines**: 164
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Function too long

- **Lines 21–164**: The anonymous function registered via `make_builtin_named` is ~144 lines, covered by deeply nested `match` expressions (including three levels of nesting for `names_from_col` / `values_from_col` type validation). The main logic body (lines 54–161) spans over 100 lines and includes row-key construction, hash-index building, pre-computed lookup tables, column reconstruction, and pivot-value resolution.

  **Fix**: Extract `build_row_groups` (lines 66–91), `precompute_lookups` (lines 95–103), `reconstruct_id_columns` (lines 106–127), and `build_pivot_columns` (lines 131–153) as top-level functions. This would eliminate the deep nesting and isolate the pivot-value resolution logic.

---

No critical issues. `Hashtbl.find_opt` is used for all hash-table lookups. `List.nth_opt` is not needed (pivot column access uses `List.find_map` with safe index lists). The `safe_get` helper (line 112) validates array bounds before access. The `match names_from_col` / `match values_from_col` nesting is exhaustive (columns 48–162). The `build_new_col` function (lines 132–151) correctly handles the column-type dispatch for the `values_from` column.
