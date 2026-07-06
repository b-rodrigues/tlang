# Review: src/packages/stats/fit_stats.ml

**Lines**: 313
**Severity summary**: 0 critical, 1 warning, 1 info

---

## WARNING: Function too long (extract_stats_row)

- **Line 90**: `extract_stats_row` spans ~146 lines (lines 90–235) with deeply nested pattern matches (up to 7 levels). The function handles PMML model-type dispatch, field extraction, and row construction in a single monolithic block.

  **Fix**: Extract model-type-specific logic into helper functions (e.g., `extract_random_forest_data`, `extract_decision_tree_data`, `extract_boosted_data`), each returning a `(n_trees, n_features)` pair. This would flatten the nesting and improve testability.

---

## INFO: Magic strings in column definitions

- **Line 251-266**: Column names like `"r_squared"`, `"adj_r_squared"`, `"f_statistic"`, `"log_lik"` etc. are hardcoded as string literals in `build_stats_dataframe`. These are also duplicated as lookup keys in `extract_stats_row` (e.g., line 206, 219, 231) — if a key name ever diverges between the two functions, the column will silently be `None`.

  **Fix**: Define a variant or module-level constants for the canonical stat names to ensure a single source of truth.
