# Review: src/packages/colcraft/unite.ml

**Lines**: 144
**Severity summary**: 0 critical, 2 warnings, 0 info

---

## WARNING: Function too long

- **Lines 28–144**: The anonymous function registered via `make_builtin_named` is ~117 lines, handling both positional and named argument parsing for `col`, source column detection, per-row value string extraction, and column insertion logic.

  **Fix**: Extract `unite_parse_args`, `get_val_str` (already a named inner helper at line 87 — good), and `build_unite_columns` as top-level functions.

---

## WARNING: Complex column-insertion logic using mutable refs

- **Lines 122–138**: The column insertion logic uses a `ref`-based state machine (`inserted` flag) to decide where to place the new united column. The `List.iter` with side effects on `final_columns` and `inserted` is fragile and hard to reason about.

  **Fix**: Use a functional approach — `List.fold_left` or `List.map` with an explicit accumulator that tracks whether the new column has been inserted.

---

No critical issues. All column-type matches for `get_val_str` are exhaustive (lines 88–107). Array indices are bounded by `orig_nrows` from `Arrow_table.num_rows`. Column existence is validated before access (lines 82–84). No unsafe `List.nth`, `Option.get`, or unguarded `Hashtbl.find` calls.
