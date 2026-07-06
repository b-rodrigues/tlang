# Verification Report: src/arrow/arrow_owl_bridge.ml

## File: src/arrow/arrow_owl_bridge.ml

### Finding: `linreg_multi` exceeds 80-line threshold (Original lines: 391-558)

**Actual lines**: 391-558 (168 lines)
**Status**: CONFIRMED

**Evidence**: The function spans from line 391 to line 558. It handles weight normalization, design matrix construction, X'X / X'y computation, normal equations solving, fitted values, residuals, SS, R², adj R², standard errors, t-stats, p-values, hat matrix, Cook's distance, standardized residuals, log-likelihood, AIC, BIC, and vcov — all in a single function.

**Verdict**: 168 lines, more than double the 80-line guideline.

---

### Finding: Mutable `ref` accumulation without functional alternative (Original lines: 92-113, 131-142, 422-523)

**Actual lines**: 92-113, 131-142, 422-428, 430-436, 442-448, 454-458, 460-466, 487-506
**Status**: CONFIRMED

**Evidence**:
- Lines 92-98: `sum_xy`, `sum_xx` refs in `linreg`, plus cc_res/cc_tot at 103-109
- Lines 131-139: `sum_xy`, `sum_xx`, `sum_yy` refs in `pearson_cor`
- Lines 422-428: `s` ref in `xtx` construction (nested loops)
- Lines 430-436: `s` ref in `xty` computation
- Lines 442-448: `s` ref in fitted values computation
- Lines 454-458: `s` ref in weighted mean_y
- Lines 460-466: `ss_res`, `ss_tot` refs
- Lines 498-505: `h` ref in hat matrix diagonal computation

**Verdict**: Widespread ref-based mutable accumulation in numerical code. While this is a common OCaml performance pattern, the code review checklist correctly flags this. For simple sums/counts, `Array.fold_left` is equally efficient; for the nested loops (XXT construction), ref-based loops are a pragmatic choice.

---

### Finding: `log_gamma` latent `-inf` when `v ≤ 0` (Original lines: 305-307)

**Actual lines**: 305-307
**Status**: CONFIRMED

**Evidence**:
```
305:   if v < 0.5 then
306:     let pi = Float.pi in
307:     log pi -. log (Float.abs (sin (pi *. v))) -. log_gamma (1.0 -. v)
```
**Verdict**: When `v = 0.0`, `sin(pi * 0.0) = 0.0`, so `log (Float.abs 0.0) = log 0.0 = -inf`. When `v = 1.0`, `sin(pi) ≈ 0.0` (floating-point), same problem. However, as the review correctly notes, this is currently not reachable — `log_gamma` is only called from `betai` with arguments `aa` and `bb` which are `df / 2.0` where `df > 0`. The function `betai` at line 320 is called with `a = df/2` from `t_pvalue` (line 373) and `f_pvalue` (line 380). So the `v < 0.5` path is reachable only if the caller passes `a < 0.5` or `b < 0.5`, which doesn't happen with current callers. Latent bug, not currently triggered.
