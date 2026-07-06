# Verification Report: `src/pipeline/builder_internal.ml`

Review file: `review-src_pipeline_builder_internal.ml.md`

---

## File: src/pipeline/builder_internal.ml

### Finding: Hashtbl.find Without Guard — Repeated Use (Original line: 406, 417, 418, 435, 506, 640, 647, 661, 662, 758, 759)

**Actual lines**: 406, 417, 418, 419, 435, 506, 640, 641, 642, 646, 661, 662, 758, 759
**Status**: CONFIRMED

**Evidence**: All nodes are pre-seeded into `statuses` on line 364 via `List.iter (fun n -> Hashtbl.add statuses n "Pending") node_names`. Every `Hashtbl.find statuses name` call throughout the function (lines 406, 417, 418, 419, 435, 506, 640, 641, 642, 646, 661, 662, 758, 759) relies on this invariant. The review's line count was missing line 641 (a second comparison in a multi-line conditional) and mis-counted line 646 as 647 — but the issue is real.

**Verdict**: The code is currently safe only because of the invariant established on line 364. Any refactoring that changes `node_names` or moves the seeding could introduce `Not_found` crashes. The review's recommendation to use `Hashtbl.find_opt` with explicit error handling is valid defensive practice per the OCaml Code Review Checklist ("No `Hashtbl.find` without a `find_opt` alternative").

---

### Finding: Unvalidated String.sub with Unbounded Indices (Original line: 396, 454)

**Actual lines**: 396, 450
**Status**: NEEDS_REVISION

**Evidence**: 
- Line 396: `let sub = String.sub line start_idx (String.length line - start_idx) in` — This is the same pattern as the review describes. Since `contains_substring_idx` at line 139 checks `i + len_p > len_l` before returning an index, when it returns a non-negative index, `start_idx + len_p <= String.length line`, so `start_idx < String.length line` and the substring length is positive. Safe *by semantic contract only*.
- Line 454: The review cites this for the same issue, but line 454 is `String.sub sub 0 end_idx` — this is a different `String.sub` pattern (sub-indexing an already-extracted substring with a validated `end_idx`). The actual matching pattern is at **line 450**: `let sub = String.sub line start_idx (String.length line - start_idx) in`.

**Verdict**: The line 396 pattern is structurally fragile but not actually buggy under current semantics. The line 454 reference in the review is wrong — the same risky pattern actually occurs at line 450, not 454. The review's fix (`max 0 (String.length line - start_idx)`) would be a valid belt-and-suspenders addition.

**Better fix**: Use a safe extraction helper for both locations (lines 393-400 and 448-455):
```ocaml
(* Extracted helper *)
let extract_store_path line =
  let start_idx = contains_substring_idx line "/nix/store/" in
  if start_idx >= 0 then
    let sub = try String.sub line start_idx (String.length line - start_idx) 
              with Invalid_argument _ -> "" in
    let end_idx = try String.index sub '\'' with _ -> 
                  try String.index sub ' ' with _ -> 
                  String.length sub in
    try String.sub sub 0 end_idx with Invalid_argument _ -> ""
  else ""
```

---

### Finding: Function Too Long — build_pipeline_internal (Original line: 89-839)

**Actual lines**: 89-839
**Status**: CONFIRMED

**Evidence**: The function spans ~750 lines (89 through 839). It contains parsing, Nix operations, I/O, logging, error recovery, dry-run logic, and status reconciliation in one monolithic function.

**Verdict**: Valid structural observation, not a correctness bug. The suggested decomposition targets (argument parsing, Nix-instantiate, dry-run, build callback, log saving, reconciliation, summarization) are reasonable extraction points.

---

### Finding: Silent Ignoring of Write Failures (Original line: 610)

**Actual line**: 610
**Status**: CONFIRMED

**Evidence**: `ignore (write_file (Filename.concat pipeline_dir "last_build_drvs.json") drv_json)` — the `ignore` discards the `Result` from `write_file`. If the write fails, the error is completely swallowed with no logging.

**Verdict**: The review is correct. The suggestion to log a warning is the minimum fix. Note that `save_build_log` at line 579 returns the `write_file` result and is properly handled at lines 719-720 (the return value is matched against `Ok ()` / `Error msg`), confirming this pattern was recognized elsewhere but missed here.

---

### Finding: Catch-all Exception Handlers Masking Errors (Original lines: 134, 402, 397-399, 456, 598)

**Actual lines**: 134, 402, 397-399, 456, 598
**Status**: CONFIRMED

**Evidence**:
- Line 134: `with _ -> false` in `contains_substring` — any exception from `String.sub` is treated as "not found"
- Lines 397-399: nested `try String.index sub '\'' with _ -> try String.index sub ' ' with _ -> String.length sub` — two catch-all handlers inside the extraction block
- Line 402: `with _ -> ""` — catch-all on the entire derivation extraction (lines 393-402)
- Line 456: `with _ -> "<path>"` — identical pattern in the error-handling branch
- Line 598: `with _ -> []` — catches all exceptions (including JSON parse errors) from `Yojson.Safe.from_file`

**Verdict**: All confirmed. The catch-all handlers are intentional "best effort" patterns but mask real bugs. The review's suggestion to use specific exception handlers and/or log unexpected exceptions is reasonable.

---

### Finding: Redundant `max 0` in `nix_verbosity_args` (Original line: 22)

**Actual line**: 22
**Status**: CONFIRMED

**Evidence**: Line 21: `if verbose <= 0 then []`. Line 22: `else List.init (max 0 (verbose - 1)) (fun _ -> "--verbose")`. Because of the `<= 0` guard on line 21, by the time we reach line 22, `verbose >= 1`, so `verbose - 1 >= 0`. `max 0 (verbose - 1)` is always `verbose - 1`.

**Verdict**: Dead code. The review's fix (`List.init (verbose - 1)`) is correct.

---

### Finding: Unused Variable Binding (Original line: 278)

**Actual line**: 278
**Status**: CONFIRMED (intentional, no fix needed)

**Evidence**: `let _ = Str.search_forward re output !pos in` — the result is intentionally discarded because the side effect (advancing `pos` via `Str.match_end ()` on line 282) is the purpose of the call.

**Verdict**: The review correctly notes no fix is needed. The suggestion to add a comment is reasonable.
