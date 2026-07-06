# Fix Plan — T Language Codebase Quality Audit

**Date**: 2026-07-05
**Files reviewed**: 249/249 `.ml` source files
**Review files**: 85 (80 individual + 5 batch)
**Verification files**: 47
**Findings**: 50 CRITICAL, 163 WARNING, 125 INFO (raw reviews)
**After verification**: 48 CRITICAL confirmed, 15 false positives identified, 26 total false positives across all severities

---

## Verification Summary

All 85 review files have been independently verified against actual source code:

| Metric | Count |
|--------|-------|
| Findings verified | 346 |
| CONFIRMED | 297 |
| FALSE_POSITIVE | 26 |
| NEEDS_REVISION | 23 |
| False positive rate | 7% |

### False Positives Removed (26 items — no fix needed)

| # | File | Finding | Why false |
|---|------|---------|-----------|
| 1 | `ast.ml` | levenshtein array access critical | Review admits no bug exists |
| 2 | `eval.ml` | strip_dollar_prefix duplication | Not actually duplicated |
| 3 | `parser.mly` | empty comment blocks | Contain '...' separator text, not whitespace |
| 4 | `builder_utils.ml` | eval_node_store_path String.sub | `len >= 2` guard already prevents OOB |
| 5 | `builder_utils.ml` | run_command_capture dead code | Actually used by 2 callers |
| 6 | `builder_read_node.ml` | early-return bypasses log | `when which_log = None` guard prevents it |
| 7 | `arrow_compute.ml:543` | List.hd on empty groups | Already has `[] -> empty_na` guard |
| 8 | `scaffold.ml` | catch-all in copy_text_file | Exception IS re-raised after copy |
| 9 | `scaffold.ml` | Sys.argv.(0) bounds | Wrapped in try/with on line 40 |
| 10 | `r_description_resolver.ml` | repetitive binary check | Design choice, not a bug |
| 11 | `r_description_resolver.ml` | find_file_recursively ref | Justified for filesystem traversal |
| 12 | `toml_parser.ml` | parse_tproject_toml 76 lines | Within acceptable range |
| 13 | `toml_parser.ml` | parse_dependencies git+tag only | Documented limitation, not a bug |
| 14 | `toml_parser.ml` | parse_description empty defaults | Intentional by design |
| 15 | **`t_boolean.ml`** | **List.nth on empty list (CRITICAL)** | **Explicitly guarded by `List.length l > 0` check** |
| 16 | `t_explain.ml` | List.filteri usage | Part of OCaml stdlib since 4.10 |
| 17 | `lens.ml` | List.nth:117 | Guarded by length check |
| 18 | `lens.ml` | over_fn dead code | Actually called from register |
| 19 | `lm.ml` | add_diagnostics duplicate | Wrong file reference |
| 20 | `t_native_scoring.ml` | unused open Ast | Necessary for Ast.value references |
| 21 | `string_ops.ml` | length on VString | Intentional type-checking behavior |
| 22 | `pipeline_gc.ml` | --*) comment | Valid OCaml comment closure |
| 23 | `package_doctor.ml` | read_script_expr offset | Review misidentified calculation |
| 24 | `package_doctor.ml` | String.sub bounds | Guard condition is correct |
| 25 | `package_doctor.ml` | run_doctor too long | System-level orchestrator, acceptable |
| 26 | `package_doctor.ml` | missing docstrings | Helper functions, not public API |

---

## How to Use This Plan

1. Work **file by file** — each source file with CRITICAL issues must be fixed individually.
2. Read the **review file** in `big-refactor/review-*.md` for detailed findings.
3. Read the **verification file** in `big-refactor/verify-*.md` for confirmation against source.
4. After fixing a file, run `dune build && dune runtest`, and for stats: `make golden-quick`.
5. Commit with: `fix(filename): <brief description>`

---

## Priority Tiers (Verified)

### Tier 1 — Crash-Level Issues (Fix First)

These **will crash the evaluator** with uncaught OCaml exceptions, reachable from user T code.

| # | File | Line(s) | Issue | Fix |
|---|------|---------|-------|-----|
| 1 | `factors.ml` | 244 | `x_arr.(i)` when f_arr and x_arr lengths mismatch | Length guard + VError |
| 2 | `arrow_table.ml` | 581, 588, 590, 595 | `invalid_arg` in `flatten_list_column` | Return VError |
| 3 | `arrow_table.ml` | 837 | `assert (!j = new_nrows)` | Explicit VError check |
| 4 | `arrow_bridge.ml` | 145, 268 | `raise (Invalid_argument ...)` | Return VError |
| 5 | `compare.ml` | 51 | `raise (Failure ...)` when no tidy table | Return VError |
| 6 | `pmml_utils.ml` | 675, 719 | `raise Invalid_argument` on malformed PMML | Return structured error |
| 7 | `serialization.ml` | 236–298, 425–464 | `invalid_arg` for unsupported JSON types | Return `Error` variant |
| 8 | `math_utils.ml` | 469, 484 | `a.(0)` on empty matrix | Empty-check + VError |
| ~~9~~ | ~~`t_boolean.ml`~~ | ~~403, 404~~ | ~~FALSE POSITIVE — guarded by `List.length > 0`~~ | No fix needed |
| 9 | `r_description_resolver.ml` | 103, 126 | `String.sub` negative length on empty `import()` | Validate string length |

### Tier 2 — Silent Data Corruption (Fix Second)

Wrong results without crashing — NaN-unsafe sorting, float equality.

| # | File | Issue | Fix |
|---|------|-------|-----|
| 10 | `cov.ml` | Polymorphic `compare` on float arrays | `Array.sort Float.compare` |
| 11 | `cv.ml` | Polymorphic `compare` + `m = 0.0` | `Float.compare` + epsilon |
| 12 | `fivenum.ml` | Polymorphic `compare` × 2 | `Float.compare` |
| 13 | `iqr.ml` | Polymorphic `compare` | `Float.compare` |
| 14 | `kurtosis.ml` | Polymorphic `compare` + float `=` | `Float.compare` + epsilon |
| 15 | `mad.ml` | Polymorphic `compare` | `Float.compare` |
| 16 | `median.ml` | Polymorphic `compare` | `Float.compare` |
| 17 | `skewness.ml` | Polymorphic `compare` + float `=` | `Float.compare` + epsilon |
| 18 | `trimmed_mean.ml` | Polymorphic `compare` | `Float.compare` |
| 19 | `winsorize.ml` | Polymorphic `compare` | `Float.compare` |
| 20 | `normalize.ml` | Float `=` for zero guard | Epsilon |
| 21 | `scale.ml` | Float `=` for zero guard | Epsilon |
| 22 | `standardize.ml` | Float `=` for zero guard | Epsilon |
| 23 | `t_native_scoring.ml` | Float equality on floats (348, 353) + 2× `Hashtbl.find` (342, 368) | Epsilon + `find_opt` |

### Tier 3 — Fragile Guards (Fix Third)

Not crashing now, but a code change could trigger exceptions.

| # | File | Line(s) | Issue | Fix |
|---|------|---------|-------|-----|
| 24 | `eval.ml` | 1998 | `List.hd offenders` — guarded but fragile | Pattern match |
| 25 | `eval.ml` | 2538 | `List.nth items index` — guarded | `List.nth_opt` |
| 26 | `t_complete.ml` | 193 | `List.nth` — guarded | `List.nth_opt` |
| 27 | `expand.ml` | 131 | `List.nth` — guarded | `List.nth_opt` |
| 28 | `lm.ml` | 86, 92 | `List.map2` mismatched arrays | Validate lengths |
| 29 | `t_explain.ml` | 135–138 | `List.assoc` flagile guard | `List.assoc_opt` |
| 30 | `ast.ml` | 420 | Structural equality on hashtable keys | Document or dedicated key type |
| 31 | `builder_utils.ml` | various | `Hashtbl.find` without `find_opt` | `find_opt` |
| 32 | `builder_read_node.ml` | various | `Hashtbl.find` without `find_opt` | `find_opt` |
| 33 | `builder_internal.ml` | various | `Hashtbl.find` without `find_opt` × 2 | `find_opt` |
| 34 | `parser.mly` | various | `List.hd` × 2 + uncaught exceptions | Pattern match |
| 35 | `lexer.mll` | various | Edge case in token construction | Add guard |
| 36 | `nix_generator.ml` | 653–670 | IO exceptions escape `install_flake` | Add try/with |
| 37 | `pipeline_expand.ml` | 399, 411, 414, 499, 513 | 3× `Hashtbl.find` + 2× `List.nth` | `find_opt` + `nth_opt` |

### Tier 4 — Package Manager IO Safety

| # | File | Issue | Fix |
|---|------|-------|-----|
| 38 | `update_manager.ml` | `close_in` without `Fun.protect` | Use `Fun.protect` |
| 39 | `package_loader.ml` | IO leak + catch-all | `Fun.protect` + specific handling |
| 40 | `release_manager.ml` | 2× process leak + 2× catch-all | `Fun.protect` + specific handling |
| 41 | `r_description_resolver.ml` | catch-all hides errors (176, 264) | Match specific exceptions |
| 42 | `tdoc_parser.ml` | `open_in` unguarded — Sys_error crash | Wrap in try/with or `In_channel` |
| 43 | `tdoc_registry.ml` | `open_out` unguarded — Sys_error crash | Same |
| 44 | `file_ops.ml` | Catch-all in `read_file` | Specific exception matching |

---

## Fix Workflow (Per File)

1. Read the review file: `big-refactor/review-src_<path>.md`
2. Read the verification: `big-refactor/verify-src_<path>.md`  
3. Apply the fix only for CONFIRMED findings
4. Run: `dune build && dune runtest`
5. Stats changes: also run `make golden-quick`
6. Commit: `fix(<filename>): <description>`

---

## Files With No Critical Issues

These have only WARNING or INFO after verification (safe to defer):

- **All math/** package files (26 files, verified clean)
- **All dataframe/** package files (10 files, verified clean)
- **Most colcraft/** files (clean except t_complete + expand)
- **All core/** package files (WARNING/INFO only)
- **All base/** package files (verified clean)
- **All explain/** package files (1 WARNING)
- **scaffold.ml** (fully cleared — both findings were false positives)
- **package_doctor.ml** (fully cleared — all findings were false positives)
- **lens.ml** (fully cleared — both findings were false positives)
- **diff.ml, chrono.ml, repl.ml** (WARNING/INFO only)
- **pipeline misc files** (WARNING/INFO only)
