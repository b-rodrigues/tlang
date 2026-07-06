# Review: src/packages/colcraft/joins.ml

**Lines**: 451
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Function too long

- **Lines 174–282**: `join_impl` is ~108 lines and handles argument parsing, hash-index building, left/right iteration, the join-kind dispatch (Left/Inner/Full/Semi/Anti), and full-join unmatched-row appending all in one function. The match on `kind, matches` (line 229) has 6 branches that mix concerns of matching logic with row construction.

  **Fix**: Extract `build_hash_index` (lines 210–219), `process_left_row` (lines 222–247), and `append_unmatched_right` (lines 250–266) as top-level functions. These already exist as local logic but would benefit from named extraction.

---

No critical issues. `Hashtbl.find_opt` is used consistently. `List.nth_opt` is used (not bare `List.nth`). `List.assoc_opt` is used. The `merge_left_right` helper correctly handles the backfill of join-key values. `right_projection` correctly deconflicts column names with `_y` suffix and `make_name_unique`. All pattern matches are exhaustive.
