# Review: `src/packages/stats/` — Batch 2 (41 files)

**Audit date**: 2026-07-05
**Scope**: Read-only code quality audit per AGENTS.md checklist.

---

# Review: `src/packages/stats/add_diagnostics.ml`

**Lines**: 109
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/anova.ml`

**Lines**: 113
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Mutable ref used where functional fold would do

- **Lines 55–86**: Three mutable `ref` cells (`results`, `prev_dev`, `prev_df`) drive an imperative accumulation loop using `List.iteri`. Both `results` and `(prev_dev, prev_df)` could be expressed as a `List.fold_left` or `List.fold_left_map`, eliminating the mutable state entirely.

  **Fix**: Replace `List.iteri` + `ref` with a `List.fold_left` that threads the accumulator and `prev_dev`/`prev_df` state through the fold.

---

# Review: `src/packages/stats/basis.ml`

**Lines**: 124
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Mutable ref used where list accumulation with fold would do

- **Lines 115–119**: `res_cols` is a `ref []` accumulated in an imperative `for` loop, then `List.rev`'d at the end.

  **Fix**: Use `List.init` and `List.map` (or a single `List.rev_map` of `1..d`) to build `res_cols` functionally.

---

# Review: `src/packages/stats/coef.ml`

**Lines**: 40
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/compare.ml`

**Lines**: 109
**Severity summary**: 1 critical, 1 warning, 0 info

---

## CRITICAL: `raise (Failure ...)` in user-facing code path

- **Line 51**: `raise (Failure (Printf.sprintf "Model %s has no tidy coefficient table." name))` — This raises a raw OCaml exception when a model lacks a `_tidy_df` entry. Per AGENTS.md rule #3, user-facing code must return `VError`, never raise.

  **Fix**: Replace the `try`/`with` / `raise (Failure ...)` pattern at lines 42–54 and 108 with a pure `match` that returns `Error.type_error` directly. The `Failure` wrapping and unwrapping is unnecessary.

## WARNING: Mutable ref for list accumulation

- **Lines 58–68**: `all_terms` is a `ref []` accumulated via `List.iter` + `:=`, then `List.rev`'d.

  **Fix**: Collect terms using `List.fold_left`/`List.fold_right` with a `Set` (or `Hashtbl`) threaded functionally.

---

# Review: `src/packages/stats/conf_int.ml`

**Lines**: 79
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/cor.ml`

**Lines**: 109
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/cov.ml`

**Lines**: 122
**Severity summary**: 1 critical, 0 warning, 0 info

---

## CRITICAL: Polymorphic `compare` on float arrays

- **Line 49**: `Array.sort compare arr` and **Line 50** (within `quantile` helper). `compare` on floats gives unexpected results for `NaN` (e.g., `Nan.compare Nan = 0` but `nan = nan` is false). This can silently produce wrong sort orders when data contains `NaN`, `infinity`, or `neg_infinity`.

  **Fix**: Replace with `Array.sort Float.compare arr` and `Array.sort Float.compare arr` respectively.

---

# Review: `src/packages/stats/cv.ml`

**Lines**: 99
**Severity summary**: 2 critical, 0 warning, 0 info

---

## CRITICAL: Polymorphic `compare` on float arrays

- **Line 49**: `Array.sort compare arr` — Same issue as `cov.ml`. Using polymorphic `compare` on floats can produce incorrect sort order with `NaN` values.

  **Fix**: `Array.sort Float.compare arr`.

## CRITICAL: Float equality (`=`) used instead of epsilon comparison

- **Lines 82, 95**: `if m = 0.0 then ...` — The mean `m` and standard deviation `s` are computed via floating-point arithmetic; exact equality against `0.0` is unreliable due to rounding. A divide-by-zero or near-zero check should use a small epsilon (e.g., `Float.abs m < 1e-15`).

  **Fix**: Replace `m = 0.0` with `Float.abs m < 1e-15` (or `Float.abs m < Float.epsilon`).

---

# Review: `src/packages/stats/deviance.ml`

**Lines**: 34
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/df_residual.ml`

**Lines**: 34
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/dispersion.ml`

**Lines**: 40
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/fivenum.ml`

**Lines**: 116
**Severity summary**: 1 critical, 0 warning, 0 info

---

## CRITICAL: Polymorphic `compare` on float arrays

- **Lines 49, 62**: `Array.sort compare arr` and `Array.sort compare arr` — Two uses of polymorphic `compare` on float arrays (in `quantile` helper at line 49 and `fivenum_tukey` at line 62). The `fivenum` result depends on correct ordering; `NaN` would silently corrupt output.

  **Fix**: Replace both with `Array.sort Float.compare arr`.

---

# Review: `src/packages/stats/huber_loss.ml`

**Lines**: 36
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/iqr.ml`

**Lines**: 89
**Severity summary**: 1 critical, 0 warning, 0 info

---

## CRITICAL: Polymorphic `compare` on float arrays

- **Line 49**: `Array.sort compare arr` — Polymorphic `compare` on float array in `quantile` helper.

  **Fix**: `Array.sort Float.compare arr`.

---

# Review: `src/packages/stats/kurtosis.ml`

**Lines**: 99
**Severity summary**: 2 critical, 0 warning, 0 info

---

## CRITICAL: Polymorphic `compare` on float arrays

- **Line 49**: `Array.sort compare arr` — Polymorphic `compare` on float array in `quantile` helper.

  **Fix**: `Array.sort Float.compare arr`.

## CRITICAL: Float equality (`=`) used instead of epsilon comparison

- **Lines 81, 95**: `if m2 = 0.0 then ...` — Variance `m2` is a computed float; exact equality against `0.0` is unreliable due to floating-point rounding.

  **Fix**: Replace `m2 = 0.0` with `Float.abs m2 < 1e-15` (or similar small epsilon).

---

# Review: `src/packages/stats/mad.ml`

**Lines**: 77
**Severity summary**: 1 critical, 0 warning, 0 info

---

## CRITICAL: Polymorphic `compare` on float arrays

- **Line 49**: `Array.sort compare arr` — Polymorphic `compare` on float array in `quantile` helper.

  **Fix**: `Array.sort Float.compare arr`.

---

# Review: `src/packages/stats/max.ml`

**Lines**: 79
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Mutable ref for tracking max and error state across loops

- **Lines 27–47, 49–69**: `max_val`, `has_values`, `had_error` are `ref` cells driven by `List.iter` and `for` loops. While this is a common OCaml pattern, the same logic could be expressed as a `fold` over the array or list.

  **Fix**: Use `Array.fold_left` with a tuple accumulator `(has_values, max_val, error)`.

---

# Review: `src/packages/stats/mean.ml`

**Lines**: 56
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/median.ml`

**Lines**: 81
**Severity summary**: 1 critical, 0 warning, 0 info

---

## CRITICAL: Polymorphic `compare` on float arrays

- **Line 49**: `Array.sort compare arr` — Polymorphic `compare` on float array in `quantile` helper.

  **Fix**: `Array.sort Float.compare arr`.

---

# Review: `src/packages/stats/min.ml`

**Lines**: 79
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Mutable ref for tracking min and error state across loops

- **Lines 27–47, 49–69**: Same pattern as `max.ml` — `ref` cells driving imperative iteration.

  **Fix**: Use `Array.fold_left` with a tuple accumulator.

---

# Review: `src/packages/stats/mode.ml`

**Lines**: 33
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/nobs.ml`

**Lines**: 34
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/normalize.ml`

**Lines**: 49
**Severity summary**: 1 critical, 0 warning, 0 info

---

## CRITICAL: Float equality (`=`) used instead of epsilon comparison

- **Line 47**: `if mx = mn then Error.value_error ...` — `mx` and `mn` are computed via `List.fold_left min infinity xs` and `List.fold_left max neg_infinity xs`. If all values are equal (e.g., `[1.0; 1.0; 1.0]`), this works, but floating-point values that are mathematically equal may differ by a tiny epsilon, causing a division by zero downstream instead of returning the error.

  **Fix**: Use `Float.abs (mx -. mn) < 1e-15` as the guard, or handle `mx -. mn = 0.0` as a separate case after the guard check.

---

# Review: `src/packages/stats/onnx_ffi.ml`

**Lines**: 38
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/predict.ml`

**Lines**: 81
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/quantile.ml`

**Lines**: 117
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/range.ml`

**Lines**: 28
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/residuals.ml`

**Lines**: 100
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/scale.ml`

**Lines**: 76
**Severity summary**: 1 critical, 1 warning, 0 info

---

## CRITICAL: Float equality (`=`) used instead of epsilon comparison

- **Line 74**: `if s = 0.0 then Error.value_error ...` — The standard deviation `s` is a computed float; exact equality against `0.0` is unreliable.

  **Fix**: Replace `s = 0.0` with `Float.abs s < 1e-15`.

## WARNING: Dead code — `quantile`, `vecf`, `has_na_rm`, `strip_na_rm` defined but never used

- **Lines 42–58, 15–21**: The functions `quantile`, `vecf`, `has_na_rm`, and `strip_na_rm` are defined at module top-level but never called in the `register` function or anywhere else in the file. These are copy-pasted from the shared helper template used by sibling files (`fivenum.ml`, `iqr.ml`, `mad.ml`, etc.) but `scale.ml`'s `register` only uses `numeric_values` and `mean`.

  **Fix**: Remove the unused definitions.

---

# Review: `src/packages/stats/score.ml`

**Lines**: 105
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/sd.ml`

**Lines**: 53
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/sigma.ml`

**Lines**: 49
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/skewness.ml`

**Lines**: 99
**Severity summary**: 2 critical, 0 warning, 0 info

---

## CRITICAL: Polymorphic `compare` on float arrays

- **Line 49**: `Array.sort compare arr` — Polymorphic `compare` on float array in `quantile` helper.

  **Fix**: `Array.sort Float.compare arr`.

## CRITICAL: Float equality (`=`) used instead of epsilon comparison

- **Lines 81, 95**: `if m2 = 0.0 then ...` — Variance `m2` is a computed float; exact equality is unreliable.

  **Fix**: Replace `m2 = 0.0` with `Float.abs m2 < 1e-15`.

---

# Review: `src/packages/stats/standardize.ml`

**Lines**: 76
**Severity summary**: 1 critical, 1 warning, 0 info

---

## CRITICAL: Float equality (`=`) used instead of epsilon comparison

- **Line 74**: `if s = 0.0 then Error.value_error ...` — Same issue as `scale.ml`.

  **Fix**: Replace `s = 0.0` with `Float.abs s < 1e-15`.

## WARNING: Dead code — `quantile`, `vecf`, `has_na_rm`, `strip_na_rm` defined but never used

- **Lines 42–58, 15–21**: Same copy-paste dead code as `scale.ml`. `quantile`, `vecf`, `has_na_rm`, and `strip_na_rm` are defined but never used in the `register` function.

  **Fix**: Remove the unused definitions.

---

# Review: `src/packages/stats/summary.ml`

**Lines**: 58
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/t_read_onnx.ml`

**Lines**: 72
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/trimmed_mean.ml`

**Lines**: 88
**Severity summary**: 1 critical, 0 warning, 0 info

---

## CRITICAL: Polymorphic `compare` on float arrays

- **Line 85**: `Array.sort compare arr` — Sorting float values with polymorphic `compare` can produce wrong ordering with `NaN`.

  **Fix**: `Array.sort Float.compare arr`.

---

# Review: `src/packages/stats/var.ml`

**Lines**: 47
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/vcov.ml`

**Lines**: 96
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/wald_test.ml`

**Lines**: 132
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: `src/packages/stats/winsorize.ml`

**Lines**: 110
**Severity summary**: 1 critical, 0 warning, 0 info

---

## CRITICAL: Polymorphic `compare` on float arrays

- **Line 49**: `Array.sort compare arr` — Polymorphic `compare` on float array in `quantile` helper.

  **Fix**: `Array.sort Float.compare arr`.

---

## Cross-cutting observations

1. **Duplicate helper code**: Nine files (`cv.ml`, `fivenum.ml`, `iqr.ml`, `kurtosis.ml`, `mad.ml`, `median.ml`, `scale.ml`, `skewness.ml`, `standardize.ml`, `winsorize.ml`) each define the same copy-pasted helper functions (`has_na_rm`, `strip_na_rm`, `numeric_values`, `quantile`, `mean`, `vecf`). These should be centralized into `Math_common.ml` or `Math_utils.ml` to eliminate duplication and prevent future drift.

2. **Dead code in `scale.ml` and `standardize.ml`**: Both define `quantile`, `vecf`, `has_na_rm`, `strip_na_rm` but only use `numeric_values` and `mean`. These unused definitions are left over from the copy-paste template.

3. **No `--# docstring** issues found**: All 41 files have proper `--#` docstrings.

4. **All files use `open Ast`** which is legitimate — all files reference AST value constructors.

5. **No files use `Option.get`**, `List.hd`, `List.tl` on unvalidated inputs, or `Hashtbl.find` without `find_opt`.
