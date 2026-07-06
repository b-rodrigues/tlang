# Review: `src/pipeline/builder_internal.ml`

**Lines**: 875
**Severity summary**: 2 critical, 3 warnings, 2 info

---

## CRITICAL: `Hashtbl.find` Without Guard — Repeated Use

- **Line 406**: `Hashtbl.find statuses name` used without a prior `Hashtbl.mem` or `Hashtbl.find_opt` check. All nodes are pre-seeded into `statuses` on line 364, so this will not crash in the current code, but it is fragile: any code path that reaches this line with a name not in the table (e.g., due to a refactoring that changes `node_names`) will raise `Not_found`.

  **Fix**: Replace all bare `Hashtbl.find statuses name` calls with `Hashtbl.find_opt` + explicit error handling, or add a defensive `Hashtbl.mem` guard.

- **Line 417**: `Hashtbl.find statuses name` — same issue.
- **Line 418**: `Hashtbl.find statuses name` — same issue.
- **Line 435**: `Hashtbl.find statuses name` — same issue.
- **Line 506**: `Hashtbl.find statuses name` — same issue.
- **Line 640**: `Hashtbl.find statuses name` — same issue.
- **Line 647**: `Hashtbl.find statuses name` — same issue.
- **Line 661**: `Hashtbl.find statuses n` — same issue.
- **Line 662**: `Hashtbl.find statuses n` — same issue.
- **Line 758**: `Hashtbl.find statuses n` — same issue.
- **Line 759**: `Hashtbl.find statuses n` — same issue.

## CRITICAL: Unvalidated `String.sub` with Unbounded Indices

- **Line 396**: `String.sub line start_idx (String.length line - start_idx)` — safe because `start_idx` is validated at line 395 to be `>= 0`, but `String.length line - start_idx` could theoretically be negative if `start_idx > String.length line` (should not happen given the semantics of `contains_substring_idx`, but fragile).

  **Fix**: Use a safe substring function or guard with `max 0 (String.length line - start_idx)`.

- **Line 454**: `String.sub line start_idx (String.length line - start_idx)` — same pattern as above.

---

## WARNING: Function Too Long — `build_pipeline_internal`

- **Line 89-839**: `build_pipeline_internal` is ~750 lines long. It contains nested state machines, I/O, logging, error recovery, dry-run logic, and reconciliation — all in one monolithic function.

  **Fix**: Extract into smaller functions:
  - Argument parsing (lines 153-255)
  - Nix-instantiate / store-path resolution (lines 258-288)
  - Dry-run handling (lines 290-361)
  - Build callback (lines 378-467)
  - Build-log saving (lines 471-580)
  - Status reconciliation (lines 631-657)
  - Result summarization (lines 660-834)

## WARNING: Silent Ignoring of Write Failures

- **Line 610**: `ignore (write_file ...)` discards the `Result` from `write_file`. If writing `last_build_drvs.json` fails, the error is silently swallowed.
- **Line 579**: In `save_build_log`, the result of `write_file log_path log_json` is the return value of the function (used as `Ok ()` / `Error msg` at lines 719-720), so this one is handled correctly.

  **Fix**: At line 610, handle the error instead of ignoring it, or log a warning.

## WARNING: Catch-all Exception Handlers Masking Errors

- **Line 134**: `with _ -> false` in `contains_substring` — any exception (e.g., from `String.sub`) is silently treated as "pattern not found".

  **Fix**: Use a more targeted exception handler (e.g., `with Invalid_argument _ -> false`).

- **Line 393-402**: `with _ -> ""` at line 402 — catch-all in derivation path extraction.
- **Line 397-399**: Nested `with _ ->` inside `String.index` calls — each masks potential errors.
- **Line 448-456**: `with _ -> "<path>"` — catch-all.

  **Fix**: Replace with specific exception handlers capturing only the expected exceptions (`Invalid_argument`, `Not_found`).

- **Line 598**: `with _ -> []` in existing-drvs loading — masks JSON parse errors.

  **Fix**: Log the parse error before returning `[]`.

---

## INFO: Redundant `max 0` in `nix_verbosity_args`

- **Line 22**: `List.init (max 0 (verbose - 1))` — `verbose` is already guarded by `<= 0` at line 21, so `verbose - 1` is always `>= 0`. The `max 0` is dead code.

  **Fix**: Simplify to `List.init (verbose - 1)`.

## INFO: Unused Variable Binding

- **Line 278**: `let _ = Str.search_forward re output !pos in` — the result is bound but discarded. This is intentional (the side effect updates `pos`), which is fine.

  **Fix**: None needed — but a comment explaining the side-effect-driven loop would help readability.
