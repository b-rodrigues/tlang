# Review: src/packages/stats/t_read_pmml.ml

**Lines**: 111
**Severity summary**: 0 critical, 0 warning, 1 info

---

## INFO: Duplicated `pmml_source_path` function

- **Line 31-36**: A local `pmml_source_path` function is defined in this file for use by `t_write_pmml_builtin`. The same functionality exists in `Pmml_utils.pmml_source_path` (used by `t_score_pmml.ml`). The local version is a simpler inline variant (works on any `VDict` rather than a model dict specifically), so they are not exact duplicates, but the naming collision is confusing.

  **Fix**: Rename the local function to something more specific (e.g., `pmml_source_path_from_dict`) or reuse `Pmml_utils.pmml_source_path` if it already handles the same shape.

No other issues found. The file follows conventions well: exhaustive pattern matches, structured error returns, no partial functions, proper `--#` docstrings.
