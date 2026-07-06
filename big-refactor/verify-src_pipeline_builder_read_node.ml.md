# Verification Report: `src/pipeline/builder_read_node.ml`

Review file: `review-src_pipeline_builder_read_node.ml.md`

---

## File: src/pipeline/builder_read_node.ml

### Finding: File Descriptor Leak — Channel Not Closed on Exception in CSV branch (Original line: 220-226)

**Actual lines**: 220-226
**Status**: CONFIRMED

**Evidence**:
```ocaml
(try
   let ch = open_in cn.cn_path in
   let content = really_input_string ch (in_channel_length ch) in
   close_in ch;
   T_read_csv.parse_csv_string content
 with exn ->
   Error.make_error ...)
```
If `really_input_string` or `in_channel_length` raises, `close_in ch` is never executed. The text branch at lines 204-210 already correctly uses `Fun.protect ~finally:(fun () -> close_in_noerr ch)` for this exact pattern. The CSV branch was missed.

**Verdict**: Confirmed fd leak. Fix: wrap with `Fun.protect` matching the text branch pattern.

**Better fix** (more specific than the review's suggestion):
```ocaml
(try
   let ch = open_in cn.cn_path in
   let content = Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
     really_input_string ch (in_channel_length ch)) in
   T_read_csv.parse_csv_string content
 with exn ->
   Error.make_error ~context:[("runtime", VString cn.cn_runtime)] FileError
     (Printf.sprintf "Failed to read CSV node `%s` from `%s`: %s" name cn.cn_path (Printexc.to_string exn)))
```

---

### Finding: File Descriptor Leak — Channel Not Closed on Exception in class file reading (Original line: 493-495)

**Actual lines**: 493-495
**Status**: CONFIRMED

**Evidence**:
```ocaml
let ch = open_in class_path in
let cls = try input_line ch |> String.trim with _ -> "unknown" in
close_in ch;
```
If `input_line ch` raises (e.g., `End_of_file`, `Sys_error`), `close_in ch` is skipped because it's outside the `try` block. The fd leaks.

**Verdict**: Confirmed. The `close_in` must be in a `finally` block.

**Better fix**:
```ocaml
let ch = open_in class_path in
let cls = Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
  try input_line ch |> String.trim with End_of_file -> "unknown"
) in
```

---

### Finding: Catch-all Exception Handlers in `read_standard_node_value` (Original lines: 149-155, 157-163, 169-183)

**Actual lines**: 154, 162, 183
**Status**: CONFIRMED (intentional best-effort pattern)

**Evidence**:
- Line 154: `with _ -> VComputedNode cn` — CSV branch fallback
- Line 162: `with _ -> VComputedNode cn` — text branch fallback
- Line 183: `with _ -> VComputedNode cn` — ONNX branch fallback

All three catch-all handlers silently fall back to `VComputedNode cn`, masking any parse/read/FFI errors.

**Verdict**: This is an intentional "best effort deserialization" pattern — `read_standard_node_value` is used when best-effort is acceptable (it always returns a value, never an error). The function signature returns `Ast.value`, not a `Result`. The review's suggestion to "log unexpected exceptions before falling back" is reasonable but would change the function's semantics. This is a design choice, not a bug. The function could be annotated with a comment documenting the best-effort semantics.

---

### Finding: Catch-all Exception Handler in class file reading (Original line: 493-495)

**Actual line**: 494
**Status**: CONFIRMED

**Evidence**: `with _ -> "unknown"` catches `End_of_file`, `Sys_error`, and every other exception.

**Verdict**: `End_of_file` on an empty class file is the only expected case. A `with End_of_file -> "unknown"` would be more targeted.

---

### Finding: Inconsistent Error Handling — Early Return Bypasses Log Matching (Original line: 486-517)

**Actual lines**: 486-517
**Status**: FALSE POSITIVE (or at least significantly mitigated)

**Evidence**: The guard on line 489 is:
```ocaml
| Some path when which_log = None && path <> "" ->
```
The `when which_log = None` guard means the env-var shortcut is ONLY taken when `which_log` is **not provided** (i.e., `None`). If the user explicitly provides a `which_log` selector, `which_log = None` is `false`, so the guard fails, and execution falls through to `| _ ->` at line 518 for the normal log-based lookup. The env-var path is only a convenience default when no log is specified.

**Verdict**: This is correct behavior. The env-var shortcut serves as a convenience default, and explicit user log selection always takes priority. The review was wrong to say it "silently ignores" `which_log`. The guard explicitly checks `which_log = None`. No fix needed.

---

### Finding: Catch-all Regex Compilation Failure in `resolve_node_artifact` (Original line: 649-652)

**Actual lines**: 638-652
**Status**: NEEDS REVISION

**Evidence**:
```ocaml
(try
   let re = Str.regexp pattern in
   ...
 with Failure _ ->
   Error (Error.make_error ValueError ...))
```
The try-block wraps both `Str.regexp` and the `List.find_opt`+`Str.search_forward` block. The review claims `Str.regexp` can raise `Invalid_argument`, making the `Failure` catch incomplete. However, according to the OCaml `Str` module documentation, `Str.regexp` raises `Failure` specifically for malformed patterns. In practice, however, some OCaml installations raise `Invalid_argument` instead for certain edge-case patterns (this is implementation-dependent). Other code in the module already catches `Failure` only (e.g., lines 380-381, 462) — inconsistent with the review claim but consistent throughout the codebase.

**Verdict**: The fix is reasonable as a defensive measure even though `Failure` is the documented exception. The principle is sound: don't let an unhandled exception propagate when there's a clear user-facing error path.

**Better fix**: Since the try-block wraps more than just `Str.regexp`, consider narrowing the scope:
```ocaml
(try
   let re = Str.regexp pattern in
   ...
 with Failure _ | Invalid_argument _ ->
   Error (Error.make_error ValueError
     (Printf.sprintf "Invalid regular expression pattern '%s' for argument `%s`." pattern arg_name)))
```

---

### Finding: `close_in` Called Without `Fun.protect` in `read_node` Class File Path (Original line: 493-495)

**Actual lines**: 493-495
**Status**: CONFIRMED (duplicate of the second CRITICAL finding above in this file)

**Evidence**: Same as the second File Descriptor Leak finding. The `close_in` on line 495 is outside the `try`/`with` and would be skipped if `input_line` raises.

**Verdict**: Already covered by the CRITICAL finding above. Apply the `Fun.protect` fix.
