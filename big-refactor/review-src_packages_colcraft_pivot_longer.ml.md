# Review: src/packages/colcraft/pivot_longer.ml

**Lines**: 135
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Function too long

- **Lines 22–135**: The anonymous function registered via `make_builtin_named` is ~114 lines, handling named-arg parsing, column validation, type inference, ID column replication, and values column construction in a single block.

  **Fix**: Extract `parse_pivot_longer_args`, `replicate_id_column`, `infer_values_type`, and `build_values_column` as named helpers. The `build_values` closure (lines 105–123) is a partial extraction — move it to a top-level function.

---

No critical issues. All column-type matches are exhaustive. Array index arithmetic (`i / n_pivot_cols`, `i mod n_pivot_cols`) is bounded correctly: `i` ranges from 0 to `orig_nrows * n_pivot_cols - 1`, so `i / n_pivot_cols` spans 0..`orig_nrows - 1` and `i mod n_pivot_cols` spans 0..`n_pivot_cols - 1`. No unsafe `List.nth`, `Option.get`, or unguarded `Hashtbl.find` calls.
