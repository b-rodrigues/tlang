# Verification: src/packages/colcraft/ + src/packages/dataframe/ — Batch 3

**30 files / 9 findings verified**. Generated 2026-07-05.

---

## File: src/packages/colcraft/nest.ml

### Finding: Long function >80 lines (Original line: 4-148)
**Actual line**: 4-148
**Status**: CONFIRMED
**Evidence**:
```ocaml
4: let nest_impl (named_args : (string option * value) list) _env =
...
148:   | [] -> Error.make_error ArityError "Function `nest` requires a DataFrame."
```
**Verdict**: `nest_impl` is ~145 lines. Contains positional/named arg resolution, column resolution, empty-group fast-path, grouped nesting with schema construction, and column reconstruction. Five distinct concerns in one function.
**Better fix**: Split into `resolve_columns`, `build_empty_result`, `build_grouped_result`.

---

## File: src/packages/colcraft/t_filter.ml

### Finding: Long function >80 lines (Original line: 81-192)
**Actual line**: 81-192
**Status**: CONFIRMED
**Evidence**:
```ocaml
81: let try_vectorize_filter (table : Arrow_table.t) (fn : value)
82:     : vectorized_predicate option =
...
192:   | _ -> None
```
**Verdict**: `try_vectorize_filter` is ~112 lines containing recursive expression matching for logical combinations of filter predicates (NOT, AND, OR) plus scalar comparison vectorization.
**Better fix**: Extract AND-handling and OR-handling from the `try_vectorize_expr` inner function into named top-level helpers.

---

### Finding: Unqualified `make_error` usage (Original line: 238, 247, 249)
**Actual line**: 238, 247, 249
**Status**: CONFIRMED
**Evidence**:
```ocaml
238:                   | _ -> had_error := Some (make_error TypeError "filter() predicate must return a Bool")
```
```ocaml
247:       | [VDataFrame _] -> make_error ArityError "Function `filter` requires a DataFrame and a predicate function."
248:       | [_; _] -> make_error TypeError "Function `filter` expects a DataFrame as first argument."
249:       | _ -> make_error ArityError "Function `filter` takes exactly 2 arguments."
```
**Verdict**: Uses bare `make_error` with unqualified `TypeError`/`ArityError` variant constructors. The file opens `open Ast` which makes these available. However, the rest of the codebase (e.g., `build_pipeline.ml`, `populate_pipeline.ml`, `pipeline_gc.ml`) consistently uses the `Error.make_error` prefixed form. This is a style inconsistency, not a compilation issue.
**Better fix**: Replace with `Error.make_error TypeError` and `Error.make_error ArityError` for consistency.

---

### Finding: Unused function parameters (Original line: 194)
**Actual line**: 194
**Status**: CONFIRMED
**Evidence**:
```ocaml
194: let register ~eval_call ~eval_expr:(_eval_expr : Ast.value Ast.Env.t -> Ast.expr -> Ast.value) ~uses_nse:(_uses_nse : Ast.expr -> bool) ~desugar_nse_expr:(_desugar_nse_expr : Ast.expr -> Ast.expr) env =
```
**Verdict**: Three labeled arguments (`_eval_expr`, `_uses_nse`, `_desugar_nse_expr`) are prefixed with `_` to suppress unused-value warnings. They exist only for interface compatibility with other `register` functions and are never used in the function body.
**Better fix**: Remove from the `register` signature in a future refactor if they are genuinely never needed.

---

## File: src/packages/colcraft/arrange.ml

### Finding: Code duplication — `"asc"` vs `"desc"` branches (Original line: 24-55 vs 56-87)
**Actual line**: 24-55, 56-87
**Status**: CONFIRMED
**Evidence**:
```ocaml
24:       | [VDataFrame df; col_val] | [VDataFrame df; col_val; VString "asc"] ->
...
56:       | [VDataFrame df; col_val; VString "desc"] ->
```
**Verdict**: The `"asc"` branch (lines 24-55) and `"desc"` branch (lines 56-87) are ~32 lines each with near-identical logic. The differences:
- `sort_by_column` boolean (`true` vs `false`)
- `compare_values` comparisons are direction-aware (`compare x y` vs `compare y x`)
- NA ordering is identical in both

This is ~64 lines of duplicated code.
**Better fix**: Parameterize `compare_values` with a direction flag. Example: `let compare_values direction a b = ...` where direction multiplies (-1 for desc).

---

## File: src/packages/colcraft/distinct.ml

### Finding: Mutable `ref` state in loops — justified (Original line: 22)
**Status**: INFO — no fix needed per review itself**
**Actual line**: 22
**Evidence**:
```ocaml
22:       let row_indices = ref [] in
23:       for i = 0 to nrows - 1 do
...
27:           row_indices := i :: !row_indices
28:         end
29:       done;
```
**Verdict**: The review correctly classifies this as acceptable. `ref []` + `for` loop for accumulating unique row indices is clear and performance-equivalent to a fold. The `Hashtbl` already handles the deduplication logic immutably. The mutable accumulation is local, single-use, and well-documented.
**Better fix**: None needed. Acceptable per AGENTS.md.

---

## File: src/packages/colcraft/drop_na.ml

### Finding: Mutable `ref` state in loops — justified (Original line: 48)
**Status**: INFO — no fix needed per review itself**
**Actual line**: 48
**Evidence**:
```ocaml
48:           let keeps = ref [] in
49:           
50:           for i = 0 to orig_nrows - 1 do
...
59:             if not has_na then keeps := i :: !keeps
60:           done;
```
**Verdict**: Same pattern as `distinct.ml`. Accumulating row indices in a loop. Clear, local, and justified.
**Better fix**: None needed.

---

## File: src/packages/colcraft/uncount.ml

### Finding: Mutable `ref` state in loops — justified (Original line: 21)
**Status**: INFO — no fix needed per review itself**
**Actual line**: 21
**Evidence**:
```ocaml
21:                let error = ref None in
22:                Array.iteri
23:                  (fun i v ->
24:                    match (!error, v) with
25:                    | (Some _, _) -> ()
26:                    | (None, VInt n) -> ...
```
**Verdict**: `error` ref short-circuits processing on first error. Documented pattern for early-exit from `Array.iteri`. Acceptable per AGENTS.md.
**Better fix**: None needed.

---

## File: src/packages/dataframe/glimpse.ml

### Finding: Mutable `ref` state in loops — justified (Original line: 30-41)
**Status**: INFO — no fix needed per review itself**
**Actual line**: 30-41
**Evidence**:
```ocaml
30:             let col_type = ref "Unknown" in
31:             let found_type = ref false in
32:             let i = ref 0 in
...
35:             while not !found_type && !i < len do
...
40:                   found_type := true
41:             done;
```
**Verdict**: Three `ref` cells for scanning the first non-NA value in each column. Imperative scan is clearer than functional alternatives (`Array.find_opt` + mapping) for this use case. Acceptable per AGENTS.md.
**Better fix**: None needed. Could use `Array.find_opt` but imperative is fine here.

---

## Files with no issues found (verified)

The following 24 files were verified to have zero findings — consistent with the review:

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
- `src/packages/dataframe/ncol.ml`
- `src/packages/dataframe/nrow.ml`
- `src/packages/dataframe/t_read_arrow.ml`
- `src/packages/dataframe/t_read_parquet.ml`
- `src/packages/dataframe/t_write_arrow.ml`
- `src/packages/dataframe/t_write_csv.ml`
- `src/packages/dataframe/t_write_parquet.ml`

Additionally confirmed absent in all files: `Option.get`, `List.hd`/`List.tl` on unvalidated lists, `Hashtbl.find` without `find_opt`, unvalidated `Array.get`/`List.nth`, raw `failwith`/`raise` in user-facing paths.

---

## Summary

| Status | Count |
|--------|-------|
| **CONFIRMED** | 5 (warning) |
| **INFO — no fix needed** | 4 |
| **NEEDS_REVISION** | 0 |
| **FALSE_POSITIVE** | 0 |
| **No issues per review** | 24 files |

The 5 confirmed warnings are:
1. `nest.ml` — function too long (145 lines)
2. `t_filter.ml` — function too long (112 lines)
3. `t_filter.ml` — unqualified `make_error` (style inconsistency)
4. `t_filter.ml` — unused function parameters (interface compatibility)
5. `arrange.ml` — ~64 lines of duplicated code for asc/desc

The 4 info items are intentional ref patterns that the review itself acknowledges as justified.
