# Review: src/packages/colcraft/separate.ml

**Lines**: 137
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Function too long

- **Lines 26–137**: The anonymous function registered via `make_builtin_named` is ~112 lines, handling named-arg parsing, regex compilation, string splitting, NA padding, and column reconstruction in a single block with up to 4 levels of nested `match`/`try`/`match` inside `match` (lines 78–135: `match col_data with` → `match sep_re_res with` → `match split_vals_res with` → `Array.map`).

  **Fix**: Extract `separate_parse_args`, `compile_separator`, `split_column_values`, and `build_separate_columns` as top-level functions to flatten the nesting.

---

No critical issues. `Str.regexp` errors are caught via `try...with Failure`. `Array.init` failures are caught. All pattern matches are exhaustive. Column existence is validated via `Arrow_table.has_column` before access. `List.nth_opt` is used for safe list access (line 113). No unsafe `Option.get` or `List.hd` usage.
