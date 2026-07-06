# Review: src/pipeline/ + src/packages/pipeline/ — Batch 1

**45 files reviewed**. Generated 2026-07-05.

---

# Review: src/pipeline/builder_copy.ml

**Lines**: 87
**Severity summary**: 0 critical, 2 warning, 1 info

---

## WARNING: Mutable refs for accumulation

- **Lines 58-59**: `let errors = ref []` and `let success_count = ref 0` used with `List.iter` + `incr` instead of a fold or `List.partition`. Acceptable for accumulating multiple errors across iterations, but `List.fold_left` on `(Ok state)` would be more functional.

  **Fix**: `List.fold_left` over nodes with a result-accumulating state.

## WARNING: `ignore` drops `Unix.mkdir` and `write_file` errors

- **Line 30**: `Unix.mkdir target_dir 0o755` — ignores failure. If `mkdir` fails (e.g. permission denied), the copy silently proceeds and may produce confusing downstream errors.

  **Fix**: Check `Unix.mkdir` result or use `Sys.file_exists` after the call.

- **Line 41-42**: `ignore (run_command_argv_exit ...)` — ignores `find`+`chmod` failures silently.

  **Fix**: At minimum log the failure; consider collecting errors.

## INFO: Magic octal literals

- **Line 30**: `0o755` is hard-coded. Already consistent with T conventions, but the function accepts `dir_mode`/`file_mode` as string parameters, yet the initial `mkdir` always uses `0o755`.

  **Fix**: Use `Scanf.sscanf dir_mode "%o"` to parse the user-provided mode for the initial `mkdir` as well.

---

# Review: src/pipeline/builder_inspect.ml

**Lines**: 87
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/pipeline/builder_logs.ml

**Lines**: 233
**Severity summary**: 0 critical, 0 warning, 1 info

---

## INFO: Catch-all `with _ ->` in JSON parsing helpers

- **Lines 52, 131**: `with _ -> false` / `with _ -> None` swallow all exceptions (including `Out_of_memory`, `Stack_overflow`, `Division_by_zero`). Acceptable here because these are filtering/logging helpers where failure safely means "no match", but would benefit from being narrowed.

  **Fix**: Catch only `Yojson.Json_error`, `Sys_error`, and `Failure` explicitly.

---

# Review: src/pipeline/builder.ml

**Lines**: 9
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found (pure include aggregator).

---

# Review: src/pipeline/builder_nix_store.ml

**Lines**: 34
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: `ignore` drops `write_file` errors

- **Lines 26, 34**: `ignore (write_file env_nix_path content)` — if the file cannot be written (e.g. `_pipeline/` does not exist, or disk is full), the error is silently discarded. Downstream Nix operations will later fail with a confusing "file not found" error.

  **Fix**: Propagate the error from `write_file` (requires changing the return type of `write_env_nix` to `unit result`), or at minimum log a warning.

---

# Review: src/pipeline/builder_populate.ml

**Lines**: 194
**Severity summary**: 0 critical, 2 warning, 0 info

---

## WARNING: Function too large

- **Lines 10-194**: `populate_pipeline` is 184 lines with deeply nested `match`/`let` chains. Hard to maintain and review.

  **Fix**: Extract `check_multi_dep_strategies`, `check_serializer_coherence`, and the `tproject.toml` parsing block as separate top-level functions.

## WARNING: Catch-all exception in tproject.toml parsing

- **Line 183**: `with _ -> [], []` — catches all exceptions when parsing `tproject.toml`. A corrupt `tproject.toml` could cause a confusing silent fallback.

  **Fix**: Catch specific exceptions (`Sys_error`, `Yojson.Json_error`, `Failure`).

---

# Review: src/pipeline/builder_write_dag.ml

**Lines**: 16
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/pipeline/nix_emit_pipeline.ml

**Lines**: 289
**Severity summary**: 0 critical, 1 warning, 1 info

---

## WARNING: Function too large

- **Lines 27-289**: `emit_pipeline` is 262 lines. Contains Nix template construction, flake resolution, R dependency handling, and Julia/Python package injection all in one function.

  **Fix**: Extract these blocks:
  - `emit_r_dependencies` (r_renv_cran_pkgs + r_git_pkgs)
  - `emit_julia_config` (has_julia, julia_build_input, julia_packages_injection)
  - `emit_flake_bindings` (flake_env_map logic)
  - The `Printf.sprintf {|...|}` multi-line string template should be a separate template-building step, not inline.

## INFO: Mutable `Hashtbl` for flake dedup

- **Lines 43-53**: `Hashtbl.create 8` used for `seen` and `flake_env_map`. Local to a single function and functionally sound, but `List.sort_uniq` on paths would be simpler.

  **Fix**: Replace `seen` hashtable with `List.sort_uniq String.compare`.

---

# Review: src/pipeline/nix_emitter.ml

**Lines**: 4
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found (pure include aggregator).

---

# Review: src/pipeline/nix_unparse.ml

**Lines**: 155
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Function too large

- **Lines 46-131**: `unparse_expr` is 85 lines of dense pattern matching over ~20 AST variants. The mutually recursive `unparse_stmt` (lines 133-153) adds another 20 lines.

  **Fix**: Split per-variant helpers (`unparse_call`, `unparse_match`, `unparse_lambda`, etc.) to keep each function under 30 lines.

---

# Review: src/pipeline/nix_utils.ml

**Lines**: 39
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/arrange_node.ml

**Lines**: 98
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/build_pipeline.ml

**Lines**: 193
**Severity summary**: 0 critical, 2 warning, 0 info

---

## WARNING: Catch-all `with _ -> ()` in `write_atelier_diagrams`

- **Lines 13, 17, 23, 27**: `try ... with _ -> ()` — swallows all errors from `pipeline_to_dot` and `pipeline_to_mermaid`. While these are non-critical side effects, a programming error in the DOT/Mermaid emitter would be silently hidden.

  **Fix**: Catch specific exception types, or log the error with `Printf.eprintf`.

## WARNING: Function too large

- **Lines 54-191**: `build_fn` is 137 lines with deeply nested validation chains (verbose, nix_options, dry_run, pipeline_name).

  **Fix**: Extract each argument validation into a named helper (e.g. `validate_verbose`, `validate_nix_options`, `validate_dry_run`).

---

# Review: src/packages/pipeline/export_artifacts.ml

**Lines**: 31
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/filter_node.ml

**Lines**: 93
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/import_artifacts.ml

**Lines**: 42
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/inspect_artifacts.ml

**Lines**: 47
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/inspect_pipeline.ml

**Lines**: 207
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Catch-all `with _ -> None` in `eval_dep_len_expr`

- **Line 55**: `with _ -> None` — catches all exceptions from evaluating dependency-length expressions. An evaluation bug would silently return `None` instead of propagating the error.

  **Fix**: Catch specific exceptions (`Error.GenericError` etc.) or let the error propagate.

---

# Review: src/packages/pipeline/jln_docs.ml

**Lines**: 23
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found (doc-only module).

---

# Review: src/packages/pipeline/mutate_node.ml

**Lines**: 152
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found. The `ref` for `first_error` is a pragmatic choice for collecting the first error in a multi-field mutation; a monadic `Result` approach would be more functional but less readable here.

---

# Review: src/packages/pipeline/node_docs.ml

**Lines**: 25
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found (doc-only module).

---

# Review: src/packages/pipeline/pipeline_args.ml

**Lines**: 8
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found. Correctly uses `nth_safe` instead of bare `List.nth`.

---

# Review: src/packages/pipeline/pipeline_cache_status.ml

**Lines**: 63
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/pipeline_copy.ml

**Lines**: 56
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found. Uses monadic `>>=` for clean error chaining.

---

# Review: src/packages/pipeline/pipeline_diff.ml

**Lines**: 142
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/pipeline_gc.ml

**Lines**: 134
**Severity summary**: 0 critical, 0 warning, 1 info

---

## INFO: Docstring terminator uses `--*` instead of `--#`

- **Line 15**: `--*)` at end of docstring block. Should be `--#`.

  **Fix**: Change `--*)` to `--#)`.

---

# Review: src/packages/pipeline/pipeline_node.ml

**Lines**: 35
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/pipeline_nodes.ml

**Lines**: 101
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/pipeline_run.ml

**Lines**: 68
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/pipeline_to_drv.ml

**Lines**: 50
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/pipeline_to_frame.ml

**Lines**: 142
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found. The mutable `Hashtbl` in `compute_depths` is documented and appropriate for memoization.

---

# Review: src/packages/pipeline/pipeline_to_store.ml

**Lines**: 44
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/pipeline_utils.ml

**Lines**: 20
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found. `nth_safe` is correctly implemented with no partial functions.

---

# Review: src/packages/pipeline/populate_pipeline.ml

**Lines**: 168
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Function too large

- **Lines 33-167**: `populate_fn` is 134 lines with sequential validation of 5 arguments using a repetitive pattern.

  **Fix**: Extract a `validate_arg` helper that abstracts the `(provided, val)` get-and-validate pattern used for `build`, `verbose`, `nix_options`, `dry_run`, `pipeline_name`.

---

# Review: src/packages/pipeline/pyn_docs.ml

**Lines**: 24
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found (doc-only module).

---

# Review: src/packages/pipeline/qn_docs.ml

**Lines**: 24
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found (doc-only module).

---

# Review: src/packages/pipeline/read_past_node.ml

**Lines**: 64
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/rename_node.ml

**Lines**: 128
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/rn_docs.ml

**Lines**: 24
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found (doc-only module).

---

# Review: src/packages/pipeline/select_node.ml

**Lines**: 99
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/pipeline/set_nix_defaults.ml

**Lines**: 40
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found. The `:=` mutation on `global_nix_defaults` is by design (session-wide defaults).

---

# Review: src/packages/pipeline/shn_docs.ml

**Lines**: 27
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found (doc-only module).

---

# Review: src/packages/pipeline/t_make_mod.ml

**Lines**: 280
**Severity summary**: 0 critical, 2 warning, 1 info

---

## WARNING: Function too large

- **Lines 58-279**: The `t_make` handler closure is ~220 lines. Contains:
  - Named argument parsing and validation (~120 lines)
  - File reading (~10 lines)
  - Parsing and evaluation (~40 lines)
  - Project name resolution from `tproject.toml` (~20 lines)

  **Fix**: Extract named argument processing into a `process_named_args` function, the `tproject.toml` name resolution into `resolve_project_name`, and the evaluation/error-handling block into `eval_pipeline_file`.

## WARNING: Multiple `ref` accumulators for error state

- **Lines 60-64**: Uses 4 mutable `ref` cells (`filename`, `nix_args`, `verbose`, `failfast`, `arg_error_opt`) when a single `Result`-typed accumulator would be cleaner.

  **Fix**: Use a `(string, int, int, bool, string list) Result.t` accumulator pattern or a record that gets updated monadically.

## INFO: Magic number in `source_location`

- **Line 9**: `max 1 (pos.Lexing.pos_cnum - pos.Lexing.pos_bol + 1)` — the `+ 1` and `max 1` are column-adjustment magic numbers that should be a named constant (e.g. `let column_offset = 1`).

  **Fix**: `let column_offset = 1` with a comment explaining the lexer is 0-based but T uses 1-based columns.

---

# Review: src/packages/pipeline/trace_nodes.ml

**Lines**: 144
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: `Hashtbl.find` without `_opt` (repeated)

- **Lines 50, 59, 104**: Uses `try Hashtbl.find tbl k with Not_found -> []` pattern instead of `Hashtbl.find_opt tbl k |> Option.value ~default:[]`. While functionally equivalent, the `_opt` variant is preferred per codebase conventions (AGENTS.md: "No `Hashtbl.find` without a `find_opt` alternative").

  **Fix**: Replace each occurrence with `Hashtbl.find_opt tbl k |> Option.value ~default:[]`.

---

# Review: src/packages/pipeline/which_nodes.ml

**Lines**: 150
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Summary

| Severity | Count |
|----------|-------|
| **Critical** | 0 |
| **Warning** | 12 |
| **Info** | 4 |

No critical issues found in the 45 files reviewed. The most common patterns are:

1. **Large functions** (6 instances): `nix_emit_pipeline.ml`, `nix_unparse.ml`, `build_pipeline.ml`, `populate_pipeline.ml`, `t_make_mod.ml`, `builder_populate.ml` — each has a function exceeding 80 lines. Extracting helpers would improve maintainability.

2. **`ignore` dropped errors** (2 instances): `builder_nix_store.ml` lines 26/34, `builder_copy.ml` line 41-42 — write and chmod failures are silently ignored.

3. **`Hashtbl.find` without `_opt`** (3 instances in `trace_nodes.ml:50,59,104`).

4. **Catch-all `with _ ->`** (3 instances in `builder_logs.ml`, `build_pipeline.ml`, `inspect_pipeline.ml`).

All functions correctly return `VError` on invalid input, use `List.assoc_opt` for safe lookups, and follow the data-first convention. No `Option.get`, `List.hd` on unvalidated lists, `failwith`, or `raise` found in user-facing paths.
