# Review: `src/packages/colcraft/mutate.ml`

**Lines**: 382
**Severity summary**: 0 critical, 1 warning, 2 info

---

## WARNING: Dead code — unreachable pattern at line 377

- **Line 377**: Pattern `(None, VDataFrame _) :: (None, _) :: _` is unreachable. It is a subset of the broader pattern at line 329: `(None, VDataFrame df) :: rest when rest <> []`, which catches all cases where the first argument is an unnamed DataFrame followed by at least one more argument.

  **Fix**: Remove the dead pattern at lines 377–378.

## INFO: Unused callback parameters in `register`

- **Line 218**: Parameters `_eval_expr`, `_uses_nse`, and `_desugar_nse_expr` are accepted but never used (prefixed with underscore to suppress warnings). This is standard for the registration interface but worth documenting or eliminating if no downstream consumer needs them.

  **Fix**: Keep as-is (interface compliance) or remove if the registration protocol is relaxed.

## INFO: Unchecked row index in `new_col.(idx)` assignment

- **Line 258**: `new_col.(idx) <- vec.(i)` — `idx` comes from `row_indices` (supplied by `Arrow_compute.get_groups`). While `row_indices` are assumed to be valid, there is no explicit bounds check that `idx < nrows` for `new_col` (which has length `nrows`). An out-of-bounds index would raise `Invalid_argument` at runtime.

  **Fix**: Add an explicit bounds guard or ensure `Arrow_compute.get_groups` contract guarantees valid indices.
