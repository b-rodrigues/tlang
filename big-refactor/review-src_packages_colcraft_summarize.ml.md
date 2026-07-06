# Review: `src/packages/colcraft/summarize.ml`

**Lines**: 360
**Severity summary**: 0 critical, 2 warning, 2 info

---

## WARNING: Inconsistent error tracking in per-group fallback paths

- **Lines 296–303**: When `Arrow_compute.group_aggregate` returns `None`, the fallback per-group evaluation does **not** update `had_error` when a `VError` is returned by `apply_aggregation`.

  Compare with lines 310–319 (the `Some result_table` / `None` branch of `Arrow_table.get_column`) where the identical fallback correctly wraps `had_error := Some result`. This means errors in this path are silently stored in the column array rather than triggering the early-exit mechanism, leading to inconsistent behavior.

  **Fix**: Wrap the `apply_aggregation env fn sub_df` call at line 304 with the same error-checking pattern used at lines 316–318.

## WARNING: Dead code in `collect_if_all_vectorizable` for empty specs

- **Line 201**: The `| [] -> Arrow_table.empty` branch inside `match specs with` is dead code in practice. While `specs` could technically be `[]` when `vectorized_pairs` is empty, the `collect_if_all_vectorizable` call at line 184 is only reached when `vectorized_pairs` is non-empty (otherwise the earlier `Ok pairs` path at line 122 would be caught before this point). Retaining the branch is defensive but dead.

  **Fix**: Remove the `| [] -> Arrow_table.empty` branch if the invariant is proven, or keep it as a documented safety net.

## INFO: Unused callback parameters in `register`

- **Line 86**: Parameters `_eval_expr`, `_uses_nse`, and `_desugar_nse_expr` are accepted but never used. Prefixed with underscore to suppress warnings. Standard interface compliance, but adds noise.

  **Fix**: Keep as-is or remove if the registration protocol is relaxed.

## INFO: Long `register` lambda body

- **Lines 109–359**: The lambda passed to `make_builtin_named` is approximately 250 lines with deep nesting (up to 6–7 levels). The `summary_result_cols` `List.map` (lines 266–351) is particularly dense, mixing batch-result extraction, per-group fallback, and error tracking.

  **Fix**: Extract `summary_result_cols` into a named helper function and split the grouped/un-grouped paths into separate top-level functions.
