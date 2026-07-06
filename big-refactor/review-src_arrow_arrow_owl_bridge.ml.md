# Review: src/arrow/arrow_owl_bridge.ml

**Lines**: 558
**Severity summary**: 0 critical, 2 warning, 1 info

---

## WARNING: `linreg_multi` far exceeds 80-line threshold

- **Line 391–558**: `linreg_multi` is 167 lines long — more than double the 80-line guideline. It handles weight normalization, design matrix construction, X'X / X'y computation, solving normal equations, fitted values, residuals, SS, R², adj R², standard errors, t-stats, p-values, hat matrix, Cook's distance, standardized residuals, log-likelihood, AIC, BIC, and vcov. Every distinct step should be a named helper.

  **Fix**: Extract phases into helpers: `build_design_matrix`, `compute_xtx_xty`, `compute_fitted_and_residuals`, `compute_goodness_of_fit`, `compute_influence_statistics`, `compute_information_criteria`.

## WARNING: Mutable `ref` accumulation in numerical code without functional alternative considered

- **Lines 92–113, 131–142, 422–523**: The file uses `ref`-based accumulation (`sum_xy := !sum_xy +. ...`) in `linreg`, `pearson_cor`, `linreg_multi`, `solve_and_invert`, and `betai`. While mutable loops are common in numerical OCaml for performance, the code review checklist flags this as a warning.

  **Fix**: For short arrays `Array.fold_left` is cleaner and equally fast for most use cases. Document that `ref` is used intentionally for performance in hot loops.

## INFO: `log_gamma` can produce `-inf` when called with `v ≤ 0`

- **Line 305–307**: `log (Float.abs (sin (pi *. v)))` produces `-inf` if `sin(pi*v) = 0.0` (e.g., `v = 0.0` or `v = 1.0`). Currently `log_gamma` is only called from `betai` with arguments strictly `> 0`, so this is not reachable from user input — but it is a latent crash if the function is ever used elsewhere.

  **Fix**: Guard `v <= 0.0` at the top of `log_gamma` and return `infinity` (the gamma function has poles at non-positive integers), or document the precondition.
