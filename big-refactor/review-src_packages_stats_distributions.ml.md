# Review: src/packages/stats/distributions.ml

**Lines**: 440
**Severity summary**: 0 critical, 1 warning, 2 info

---

## WARNING: Float equality for p = 0.5 in t_quantile

- **Line 138**: `else if p = 0.5 then 0.0` — Uses polymorphic `=` on floats to check for exact equality with 0.5. In a bisection/root-finding context, hitting exactly 0.5 is unlikely but intentional as an optimization. However, `=` on floats is not NaN-safe and may produce unexpected results with `-0.5` or near-0.5 values.

  **Fix**: Use `Float.equal p 0.5` or check `Float.abs (p -. 0.5) < 1e-15` for robustness.

## INFO: Global side effect via ref cell assignment

- **Line 160–161**: `Stats.t_quantile_fun := t_quantile` — Sets a global reference in the `Stats` module at module initialization time. This is a mutable side effect used for cross-module mutual recursion. It's documented and necessary for the circular dependency between `distributions.ml` (provides `t_quantile`) and `Stats` (provides `normal_quantile`).

  **Fix**: No action needed. This is a documented inter-module wiring pattern.

## INFO: Docstrings use `+*)` instead of `*)` to close comments

- **Lines 328, 343, 359, 374**: The qnorm, qt, qf, and qchisq docstrings end with `+*)` instead of the standard `*)`. This is a typo — the `+` at the start of the closing `*)` is likely a formatting artifact. However, since these are within `(* ... *)` comments, OCaml treats `+*)` as `+` followed by `*)`, which means the comment closes correctly at the first `*)`. The `+` is just dead text before the closing.

  **Fix**: Change `+*)` to `*)` for consistency.
