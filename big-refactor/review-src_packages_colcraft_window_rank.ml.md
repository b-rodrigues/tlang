# Review: src/packages/colcraft/window_rank.ml

**Lines**: 345
**Severity summary**: 0 critical, 0 warnings, 0 info

---

No issues found.

All match expressions are exhaustive. No unsafe `Option.get`, `List.hd`, `List.nth`, or `Hashtbl.find` (without opt) calls. Exception handling is via `Result` types throughout. `Float.equal` is used for float comparison (not structural equality). Array bounds are validated by loop invariants. Each ranked function (`row_number`, `min_rank`, `dense_rank`, `cume_dist`, `percent_rank`, `ntile`) is self-contained and correctly handles NA propagation.
