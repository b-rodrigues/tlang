# Review: src/packages/colcraft/unnest.ml

**Lines**: 147
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Function too long

- **Lines 10–130**: `unnest_impl` is ~120 lines with two large conditional branches: the zero-row case (lines 31–63, ~33 lines) and the main unnest path (lines 64–127, ~64 lines). The native-handle path (lines 82–92) and the fallback path (lines 93–125) share overlapping concerns (stacking, expanding, column reconstruction).

  **Fix**: Extract `unnest_zero_rows`, `expand_other_columns`, `unnest_via_native`, and `unnest_fallback` as named helpers. The `zero_col` function (lines 42–53) is already partially extracted but could be moved outside `unnest_impl`.

---

No critical issues. All pattern matches are exhaustive. `List.find_opt` is used for safe element searching (lines 33, 65). Expansion indices are bounded by the `!final_nrows` check. The `Arrow_table.take_col` call (line 97) receives pre-computed bounded indices. No unsafe `List.nth`, `Option.get`, or unguarded `Hashtbl.find` calls.
