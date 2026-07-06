# Review: src/packages/stats/t_score_pmml.ml

**Lines**: 196
**Severity summary**: 0 critical, 1 warning, 1 info

---

## WARNING: Function too long (t_compare_scores_pmml)

- **Line 82-165**: `t_compare_scores_pmml` is ~83 lines and contains duplicated comparison logic. The `VDataFrame` branch (lines 119–163) duplicates the loop logic from the `VVector` branch (lines 101–118), differing only in how the PMML vector is extracted. The code even has a "Refactor note" comment at line 143 acknowledging this.

  **Fix**: Extract the comparison loop (lines 105–113 and 148–156) into a shared helper function `compare_vectors(native_vec, pmml_vec)` that returns the `VDict` summary. Then have both branches call it. The `VDataFrame → VVector` extraction logic should also be a separate helper.

---

## INFO: Magic fallback path for JPMML JAR

- **Line 8**: Fallback path `"/nix/store/dummy-jpmml-evaluator.jar"` is a hardcoded development/testing placeholder. If the environment variable is unset and this file doesn't exist, the error message is descriptive. However, the hardcoded Nix store path is fragile across different Nix installations.

  **Fix**: Consider removing the hardcoded fallback and relying solely on the environment variable, or make it configurable via a second fallback mechanism.
