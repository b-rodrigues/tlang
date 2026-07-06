# Review: src/packages/colcraft/ (20 files) & src/packages/dataframe/ (10 files)

**Total files**: 30
**Severity summary**: 0 critical, 3 warning, 4 info

---

## WARNING: Long function >80 lines

### File: `src/packages/colcraft/nest.ml`

- **Lines 4–148**: `nest_impl` is ~145 lines, well over the 80-line guideline. The function handles positional/named arg resolution, empty-group fast-paths, grouped nesting, schema construction, and column reconstruction all in a single closure.

  **Fix**: Split into helpers: `resolve_columns`, `build_empty_result`, `build_grouped_result`.

### File: `src/packages/colcraft/t_filter.ml`

- **Lines 81–192**: `try_vectorize_filter` is ~112 lines, far exceeding the 80-line guideline. It contains recursive expression matching for logical combinations of filter predicates.

  **Fix**: Extract `try_vectorize_expr` (already internal) and split comparison, AND-handling, and OR-handling into named top-level helpers.

---

## WARNING: Code duplication

### File: `src/packages/colcraft/arrange.ml`

- **Lines 24–55** vs **Lines 56–87**: The `"asc"` and `"desc"` branches are nearly identical — the only differences are the `sort_by_column` boolean direction and the swapped operands in `compare_values` (e.g. `compare x y` vs `compare y x`). This is ~64 lines of duplicated logic.

  **Fix**: Parameterize the comparison function with the direction flag to eliminate the duplication.

---

## INFO: Unqualified `make_error` usage

### File: `src/packages/colcraft/t_filter.ml`

- **Lines 238, 247, 249**: Uses bare `make_error` with unqualified `TypeError`/`ArityError` instead of the project convention `Error.make_error`. Only `Ast` is opened; these names compile only if re-exported through `Ast`, but the rest of the codebase consistently uses `Error.make_error`.

  **Fix**: Replace with `Error.make_error TypeError "..."` and `Error.make_error ArityError "..."`.

---

## INFO: Mutable `ref` state in loops (justified, noted for audit)

### File: `src/packages/colcraft/distinct.ml`

- **Line 22**: `let row_indices = ref []` — accumulates unique row indices in a loop. Could be written with a fold, but the `ref` + `for` pattern is clear and performance-equivalent.

### File: `src/packages/colcraft/drop_na.ml`

- **Line 48**: `let keeps = ref []` — same pattern, accumulates row indices to keep.

### File: `src/packages/colcraft/uncount.ml`

- **Line 21**: `let error = ref None` — short-circuits processing on first error in `Array.iteri`. Documented in code.

### File: `src/packages/dataframe/glimpse.ml`

- **Lines 30–41**: `let col_type = ref "Unknown"`, `let found_type = ref false`, `let i = ref 0` — scans for first non-NA value. Could be functional (`Array.find_opt`) but the imperative scan is fine.

All four uses are acceptable per AGENTS.md ("Mutable state justified when accumulating errors in a loop over an array"). No changes needed.

---

## INFO: Unused function parameters (intentional, noted)

### File: `src/packages/colcraft/t_filter.ml`

- **Line 194**: `~eval_expr:(_eval_expr : ...) ~uses_nse:(_uses_nse : ...) ~desugar_nse_expr:(_desugar_nse_expr : ...)` — three labeled arguments exist only for interface compatibility and are never used. The `_` prefix suppresses compiler warnings.

  **Fix**: If these are never needed, consider removing them from the `register` signature in a future refactor.

---

## Files with no issues found

The following files passed all checklist items with zero findings:

- `src/packages/colcraft/count.ml`
- `src/packages/colcraft/group_by.ml`
- `src/packages/colcraft/n.ml`
- `src/packages/colcraft/n_distinct.ml`
- `src/packages/colcraft/relocate.ml`
- `src/packages/colcraft/rename.ml`
- `src/packages/colcraft/replace_na.ml`
- `src/packages/colcraft/separate_rows.ml`
- `src/packages/colcraft/slice.ml`
- `src/packages/colcraft/slice_min_max.ml`
- `src/packages/colcraft/slice_sample.ml`
- `src/packages/colcraft/t_select.ml`
- `src/packages/colcraft/ungroup.ml`
- `src/packages/colcraft/window_offset.ml`
- `src/packages/dataframe/clean_colnames.ml`
- `src/packages/dataframe/colnames.ml`
- `src/packages/dataframe/glimpse.ml`
- `src/packages/dataframe/ncol.ml`
- `src/packages/dataframe/nrow.ml`
- `src/packages/dataframe/t_read_arrow.ml`
- `src/packages/dataframe/t_read_parquet.ml`
- `src/packages/dataframe/t_write_arrow.ml`
- `src/packages/dataframe/t_write_csv.ml`
- `src/packages/dataframe/t_write_parquet.ml`

**Critical items verified absent in all files**: `Option.get`, `List.hd`, `List.tl` on unvalidated lists, `Hashtbl.find` without `find_opt`, unvalidated `Array.get`/`List.nth`/`String.get`, float `=` used instead of epsilon comparison, `failwith`/`raise`/`invalid_arg`/`assert false` reachable from user input. All error paths use `VError` return values. Data arguments are first. All functions have `--#` docstrings.
