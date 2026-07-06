# Big Refactor — Review Instructions

## Overview

You are reviewing OCaml source files in the **T programming language** codebase. You must inspect each file systematically for code quality issues, bugs, dead code, safety violations, and anti-patterns. This is a **read-only audit**: you do NOT fix anything. You write findings to a review file.

---

## How to Operate

1. Read the target file completely.
2. Analyze it using the checklist below.
3. Write findings to `big-refactor/review-<FILENAME>.md` where `<FILENAME>` is the source file name with path separators replaced by `_`.
   - Example: `src/eval.ml` → `big-refactor/review-src_eval.ml.md`
   - Example: `src/packages/stats/mean.ml` → `big-refactor/review-src_packages_stats_mean.ml.md`
4. **Do NOT modify any source code.** Only create review `.md` files.
5. One review file per source file reviewed.

---

## Output Format

Each review file MUST follow this template exactly:

```markdown
# Review: <file_path>

**Lines**: <total_line_count>
**Severity summary**: <X critical, Y warning, Z info>

---

## <SEVERITY>: <Brief title>

- **Line <N>**: <Description of the issue>

  ```ocaml
  # (optional) code snippet showing the problem
  ```

  **Fix**: <How to fix it>

---

## <SEVERITY>: <Next issue>
...
```

### Severity levels

| Level | Meaning |
|-------|---------|
| **CRITICAL** | Bug, crash, data loss, incorrect behavior at runtime. **Must fix.** |
| **WARNING** | Maintainability hazard, dead code, inefficient pattern, missing error handling. **Should fix.** |
| **INFO** | Style nit, minor redundancy, documentation issue. **Nice to fix.** |

If a file has zero findings, write:
```markdown
# Review: <file_path>

**Lines**: <N>
**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.
```

---

## Checklist (apply EVERY item to EVERY file)

### 1. CRITICAL — Partial Pattern Match
Scan **every** `match ... with` expression. Does it cover all constructors of the matched type?

- For `Ast.value` — constructors: `VInt`, `VFloat`, `VBool`, `VString`, `VSymbol`, `VList`, `VDict`, `VDataFrame`, `VModel`, `VVector`, `VNA`, `VError`, `VFunc`, `VExternalPtr`, `VType`
- For `Ast.expr_node` — constructors are in `ast.ml`
- Catch-all `| _ ->` is acceptable ONLY when the unmatched cases truly cannot occur AND is documented.
- Exception: match on `Ast.expr_node` in the evaluator (`eval.ml`) is expected to be exhaustive.

**CRITICAL if any case is missing without comment.**

### 2. CRITICAL — Unvalidated Array/List Access
- `Array.get`, `Array.set`, `.( )` syntax — is the index validated before access?
- `List.nth` — is the list long enough? Use `List.nth_opt` and handle `None`.
- `String.get`, `String.set`, `.[ ]` — is the index within bounds?
- `Bytes.get`, `Bytes.set` — same.

**CRITICAL if unvalidated.**

### 3. CRITICAL — Hashtbl.find Without Guard
- `Hashtbl.find h k` raises `Not_found` if key missing.
- Must use `Hashtbl.find_opt` or validate with `Hashtbl.mem` first.

### 4. CRITICAL — Exception Raising in User-Facing Paths
- `failwith`, `failwithf`, `invalid_arg`, `raise`, `raise_notrace`, `assert false`.
- Only acceptable for programmer errors (invariant violations), NEVER for invalid user input.
- Invalid user input must return `VError { ... }` via `Error.type_error`, `Error.value_error`, `Error.arity_error`, or `make_error`.

**CRITICAL if any `raise`/`failwith`/`invalid_arg`/`assert false` is reachable from user input.**

### 5. CRITICAL — Option.get / Option.unwrap
- `Option.get` on a potentially-`None` value.
- `Result.get_ok` / `Result.get_error` without prior check.

**CRITICAL unless the `Option` is proven non-None immediately above (e.g., `if Option.is_some x then Option.get x` — still prefer `match`).**

### 6. CRITICAL — List.hd / List.tl
- `List.hd []` raises `Failure "hd"`.
- `List.tl []` raises `Failure "tl"`.
- Prefer pattern matching: `match list with hd :: tl -> ... | [] -> ...`

### 7. CRITICAL — Silent NA Propagation
If a function receives a `VNA _` argument, does it:
  - Propagate explicitly via `Error.type_error "Function X encountered NA..."`?
  - Handle it via an `na_rm` parameter?
  - Ignore it silently (which is wrong)?

Reference: See `src/packages/stats/mean.ml` for the expected pattern.

### 8. CRITICAL — Logic Errors
- Off-by-one errors in loops.
- Incorrect accumulator initialization.
- Wrong comparison operator (`<` vs `<=`, `=` vs `==`).
- Incorrect short-circuit evaluation.
- Integer division where float division was intended.
- Float equality comparison (`=`) — use epsilon comparison instead.

### 9. WARNING — Dead Code
- Functions defined but never called within the file or from any other file.
- Variables bound but never used.
- `open` statements for modules that are never referenced.
- Unreachable branches (e.g., `if true then ...` or a wildcard before specific cases).
- Entire commented-out code blocks (not docstrings).
- Redundant `let _ = expr` where `expr` already returns `unit`.

**To check for dead functions**: grep for the function name in other `.ml` files. If you have limited context, flag the function as **suspect dead code** and mark as WARNING.

### 10. WARNING — Mutable State Used Where Functional Works
- `let v = ref ...` followed by `:=` and `!` inside what could be a `List.fold`, `Array.map`, or `List.map`.
- Exception: performance-critical hot loops, or where mutation is inherently required (e.g., random state, accumulators over large arrays).

**Flag with justification.**

### 11. WARNING — Deeply Nested Match / Conditional
- `match` inside `match` inside `match` (depth > 3) without helper functions.
- `if ... then if ... then if ... then` without `else` clarity.
- Suggest extracting inner logic to a named helper function.

### 12. WARNING — Function Too Long
- Any function exceeding ~80 lines without internal helper extraction.
- Suggest breaking into smaller functions.

### 13. INFO — Inconsistent Error Message Style
- Check error messages: do they start with `"Function `fn_name`..."`?
- Are they consistent with other functions in the same package?
- Reference: `Error.type_error "Function `filter` expects a DataFrame as first argument."`

### 14. INFO — Magic Numbers / Strings
- Hardcoded numeric literals (e.g., `0.5`, `1.96`, `100`) that should be named constants.
- Hardcoded file paths or environment variable names.

### 15. INFO — Redundant Pattern Match
- `match x with | true -> ... | false -> ...` could be `if x then ... else ...`
- `match x with | Some v -> f v | None -> default` could be `Option.fold ~some:f ~none:default x`
- `match list with | [] -> default | hd :: _ -> hd` could be `List.hd list` (but see #6 — use pattern match in _user code_)

### 16. INFO — Unused Module Open
- `open ModuleName` where no function from `ModuleName` is used in the file.

### 17. INFO — Documentation Issues
- Public function missing `--#` docstring block.
- Docstring does not match actual signature (wrong arity, wrong parameter names).
- Missing `@export` tag on registered package functions.

---

## What NOT to Do

- **DO NOT** modify any `.ml`, `.mll`, or `.mly` file.
- **DO NOT** create aliases or rename anything.
- **DO NOT** speculate about whether code works without evidence.
- **DO NOT** report style preferences that disagree with AGENTS.md conventions (e.g., data-first argument convention is intentional).
- **DO NOT** flag `NA` as missing — `NA` is intentional, missingness is handled by design.
- **DO NOT** flag `VSymbol` as an issue — known symbols are intentional (see AGENTS.md rule #6).

---

## Codebase Conventions Reference

- **Data argument always first** in function parameters. This is by design for pipe operator (`|>`).
- **`Env.add`** is used to register functions, NOT direct assignment.
- **`make_builtin`** / **`make_builtin_named`** are the standard registration wrappers.
- **`Error.type_error`**, **`Error.value_error`**, **`Error.arity_error`**, **`Error.arity_error_named`**, **`Error.make_error`** are the standard error constructors from `src/error.ml`.
- **`VError`** is returned (not raised) for user-facing errors.
- **`VNA`** represents missing values — functions should decide whether to propagate or error.
- **`VDataFrame { arrow_table; _ }`** — DataFrames are Arrow-backed.
- **`VModel`** — Machine learning models.
- **`VVector`** — Numeric vectors (float arrays).
- **Docstrings** use `--#` prefix format.

---

## Example Good Finding

```markdown
# Review: src/packages/stats/mean.ml

**Lines**: 52
**Severity summary**: 1 warning, 0 critical, 0 info

---

## WARNING: Function `mean` does not handle VModel input

- **Line 23-28**: The match on `args` does not handle `VModel`. If a model is passed, it falls through to the catch-all `| _ ->` which gives a generic arity error instead of a helpful message.

  ```ocaml
  | [VDataFrame _; VString _; VString _] -> ...
  | [VDataFrame _; VString _] -> ...
  | [VVector _; VString _] -> ...
  (* VModel missing here *)
  | _ -> Error.arity_error ...
  ```

  **Fix**: Add explicit case for `VModel`, e.g., `| [VModel _; VString _] -> Error.type_error "Function `mean` does not support Model inputs."`
```

## Example: File With No Issues

```markdown
# Review: src/packages/base/is_na.ml

**Lines**: 22
**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.
```

---

## Priority Order

Review files in this order (highest risk first):

1. `src/eval.ml` — Core interpreter
2. `src/ast.ml` — AST type definitions
3. `src/repl.ml` — REPL and CLI
4. `src/pipeline/nix_emit_node.ml` — Nix code generation (110KB)
5. `src/parser.mly`, `src/lexer.mll` — Parser/lexer
6. `src/pipeline/builder_internal.ml`, `src/pipeline/builder_read_node.ml`, `src/pipeline/builder_utils.ml`
7. `src/pipeline/pipeline_expand.ml`, `src/pipeline/pipeline_composition.ml`
8. `src/pipeline/pipeline_report.ml`, `src/pipeline/pipeline_inspect2.ml`
9. `src/diff.ml` — Diff module (1169 lines)
10. `src/packages/chrono/chrono.ml` — Chrono (1665 lines)
11. `src/packages/lens/lens.ml` — Lens (795 lines)
12. `src/packages/strcraft/string_ops.ml` — String ops (1109 lines)
13. `src/packages/stats/t_native_scoring.ml` — Native scoring (885 lines)
14. `src/packages/colcraft/factors.ml` — Factors (large)
15. `src/packages/colcraft/mutate.ml`, `summarize.ml`
16. `src/pipeline/builder_artifacts.ml`
17. `src/pipeline/pipeline_dependency_requirements.ml`
18. `src/arrow/arrow_table.ml`, `arrow_compute.ml`, `arrow_ffi.ml`, `arrow_io.ml`
19. `src/package_manager/nix_generator.ml`, `scaffold.ml`, `update_manager.ml`
20. `src/packages/core/packages.ml`, `t_boolean.ml`, `show_plot.ml`, `pretty_print.ml`
21. `src/pmml_utils.ml`
22. `src/serialization.ml`
23. `src/packages/core/converters.ml`, `t_get.ml`
24. `src/packages/stats/lm.ml`, `distributions.ml`, `math_utils.ml`
25. `src/packages/pipeline/pipeline_dag_ops.ml`, `read_node.ml`
26. `src/packages/pipeline/pipeline_set_ops.ml`, `pipeline_composition.ml`
27. `src/packages/colcraft/t_complete.ml`, `fill.ml`, `window_cumulative.ml`, `window_rank.ml`
28. `src/packages/colcraft/joins.ml`, `pivot_longer.ml`, `pivot_wider.ml`
29. `src/packages/colcraft/expand.ml`, `separate.ml`, `unite.ml`, `unnest.ml`
30. `src/packages/stats/fit_stats.ml`, `t_score_pmml.ml`, `t_read_pmml.ml`
31. `src/pipeline/build_log.ml`, `pipeline_to_ga.ml`, `pipeline_deps.ml`
32. `src/packages/explain/t_explain.ml`
33. `src/packages/dataframe/t_dataframe.ml`, `t_read_csv.ml`
34. `src/packages/math/ndarray.ml`
35. All remaining small files (< 300 lines each)
