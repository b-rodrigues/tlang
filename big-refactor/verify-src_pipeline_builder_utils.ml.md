# Verification Report: `src/pipeline/builder_utils.ml`

Review file: `review-src_pipeline_builder_utils.ml.md`

---

## File: src/pipeline/builder_utils.ml

### Finding: String.sub Potential out-of-bounds in `eval_node_store_path` (Original line: 567-571)

**Actual lines**: 566-573
**Status**: FALSE POSITIVE

**Evidence**: The guard at line 568 is:
```ocaml
if len >= 2 && res.[0] = '"' && res.[len - 1] = '"' then
  String.sub res 1 (len - 2)
```
The review claims that "when len = 1 ... a 1-character string `"` would pass the guard" and `String.sub res 1 (1 - 2)` would raise `Invalid_argument`. This is **incorrect**. The condition requires `len >= 2`, which short-circuits to `false` for `len = 1`. The substring branch is never reached for `len < 2`. The guard unambiguously prevents the out-of-bounds path.

The review's own proposed fix already includes `len >= 2 &&` — which is *already* in the code. The additional `max 0 (len - 2)` is dead code since `len >= 2` implies `len - 2 >= 0`.

**Verdict**: No bug. The existing guard `len >= 2` is sufficient. No change needed.

---

### Finding: Function Too Long — `validate_nix_options` (Original line: 42-180)

**Actual lines**: 42-180
**Status**: CONFIRMED

**Evidence**: The function spans ~138 lines and validates 9 options by repeating the same pattern 9 times with slight variations per option type. While structurally consistent, this is verbose and has high maintenance cost (adding a 10th option requires another ~15-line copy-paste block).

**Verdict**: Valid style/structural observation. The suggested list-driven fold or per-option helper would reduce duplication.

---

### Finding: Function Too Long — `run_command_stream` & `run_command_stream_argv` (Original lines: 207-293, 298-384)

**Actual lines**: 207-293 (~86 lines), 298-384 (~86 lines)
**Status**: CONFIRMED

**Evidence**: Lines 207-290 is `run_command_stream`; lines 298-383 is `run_command_stream_argv`. Both contain near-identical I/O multiplexing cores:
- Buffer creation (identical)
- `process_bytes_to` helper (identical)
- `drain` function with select loop, read, and byte processing (identical)
- `Fun.protect` with cleanup flag (identical)
- Line flushing logic (identical)

The only difference is the process-spawning call (line 209 vs lines 303-304).

**Verdict**: Valid duplication finding. Extracting the shared core would reduce ~80 lines of code and eliminate divergent maintenance.

---

### Finding: Catch-all Exception Handler in `read_file_first_line` (Original line: 202)

**Actual line**: 202
**Status**: CONFIRMED

**Evidence**: `with _ -> None` masks all exceptions — `Sys_error` (permission denied), `End_of_file`, `Invalid_argument` for bad paths, etc. The function tries to open a file, read a line, and close it. If opening fails, we get `None`. If reading fails after a successful open, the channel leaks (no `close_in` in `finally` either).

**Verdict**: The broad catch is overly permissive. The fix should also use `Fun.protect` for the channel:
```ocaml
let read_file_first_line path =
  try
    let ic = open_in path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      try Some (String.trim (input_line ic))
      with End_of_file -> None)
  with Sys_error _ -> None
```

---

### Finding: Use of Deprecated `Unix.open_process_full` with Shell Expansion (Original line: 209)

**Actual line**: 209
**Status**: CONFIRMED

**Evidence**: `run_command_stream` at line 207 uses `Unix.open_process_full cmd (Unix.environment ())` which passes `cmd` through `/bin/sh`. The sibling function `run_command_stream_argv` at line 303 correctly uses `Unix.open_process_args_full prog argv (Unix.environment ())`. Since `cmd` is a shell string, this is a shell-injection risk if it contains user-supplied data.

**Verdict**: Valid finding. Callers should be audited. If `run_command_stream` is only called with hardcoded/internal commands, the risk is effectively mitigated, but a comment documenting this is warranted.

---

### Finding: Dead Code — `run_command_capture` (Original line: 386-390)

**Actual lines**: 386-390
**Status**: FALSE POSITIVE

**Evidence**: The function IS used elsewhere:
- `src/packages/pipeline/read_node.ml:641` — `Builder_utils.run_command_capture cmd`
- `src/packages/stats/t_score_pmml.ml:43` — `Builder_utils.run_command_capture cmd`

**Verdict**: The function is actively used by two external callers. Not dead code. The review's speculation was incorrect.

---

### Finding: Unused Module Open (Original line: 43)

**Actual line**: 43
**Status**: CONFIRMED (minor style)

**Evidence**: `let open Ast in` at line 43 is scoped to `validate_nix_options`. Within this scope, only `VNA NAGeneric` on line 50 uses a `VNA` constructor without the `Ast.` prefix. No other symbols from `Ast` are used without qualification.

**Verdict**: The `open` is scoped to one function and makes the code negligibly less explicit. The review's suggestion to replace with `Ast.VNA Ast.NAGeneric` and remove the `open` is a style preference, not a correctness issue. Low priority.
