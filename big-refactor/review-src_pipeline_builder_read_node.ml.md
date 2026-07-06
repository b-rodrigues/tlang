# Review: `src/pipeline/builder_read_node.ml`

**Lines**: 675
**Severity summary**: 1 critical, 3 warnings, 1 info

---

## CRITICAL: File Descriptor Leak — Channel Not Closed on Exception

- **Line 220-226** (`read_logged_node_value`, CSV branch):
  ```ocaml
  (try
     let ch = open_in cn.cn_path in
     let content = really_input_string ch (in_channel_length ch) in
     close_in ch;
     T_read_csv.parse_csv_string content
   with exn ->
     Error.make_error ...)
  ```
  If `really_input_string` or `in_channel_length` raises an exception, `close_in ch` is never executed. The file descriptor is leaked. Compare with the `text` branch at line 204-210 which correctly uses `Fun.protect ~finally:(fun () -> close_in_noerr ch)`, and with `read_standard_node_value` at line 151 which also uses `Fun.protect`.

  **Fix**: Wrap the channel in `Fun.protect ~finally:(fun () -> close_in_noerr ch)`, following the pattern at lines 151-153 and 159-160.

- **Line 493-495** (`read_node`, class file reading):
  ```ocaml
  let ch = open_in class_path in
  let cls = try input_line ch |> String.trim with _ -> "unknown" in
  close_in ch;
  ```
  If `input_line ch` raises an exception (e.g., `End_of_file` on an empty file), `close_in ch` is skipped and the fd leaks. The catch-all `with _ -> "unknown"` does not help because `close_in` is outside the `try` block.

  **Fix**: Either move `close_in ch` into a `Fun.protect ~finally` block, or use `close_in_noerr` in an inner try-finally pattern.

---

## WARNING: Catch-all Exception Handlers Masking Errors

- **Line 149-155**: `with _ -> VComputedNode cn` in `read_standard_node_value` CSV branch — masks all exceptions from CSV parsing.

  **Fix**: Log unexpected exceptions before falling back.

- **Line 157-163**: `with _ -> VComputedNode cn` in `read_standard_node_value` text branch — same issue.

  **Fix**: Same.

- **Line 169-183**: `with _ -> VComputedNode cn` in `read_standard_node_value` ONNX branch — masks all ONNX FFI errors.

  **Fix**: Same.

- **Line 493-495**: `with _ -> "unknown"` — masks `End_of_file` and any other exception during class file reading.

  **Fix**: Use `with End_of_file -> "unknown"` to only cover the expected case.

## WARNING: Inconsistent Error Handling in `read_node` — Early Return Bypasses Log Matching

- **Line 486-517**: The function `read_node` has an early-return path for environment-variable nodes (lines 488-517). If `Sys.getenv_opt` succeeds, the function returns immediately without considering `which_log`. This means `which_log` is silently ignored when the env var is set — the user's explicit log selection is bypassed.

  **Fix**: Either document this behavior explicitly, or apply the `which_log` filter even for env-var nodes.

## WARNING: Catch-all Regex Compilation Failure in `resolve_node_artifact`

- **Line 649-652**: `with Failure _ -> Error (Error.make_error ...)` — catches only `Failure` from `Str.regexp`. However, `Str.regexp` can also raise `Invalid_argument` on certain patterns. The catch is incomplete.

  **Fix**: Add `| Invalid_argument _ -> ...` or use a catch-all `with _ ->` scoped tightly to the `Str.regexp` call.

---

## INFO: `close_in` Called Without `Fun.protect` in `read_node` Class File Path

- **Line 493-495** (detailed above in CRITICAL): The pattern `open_in` → `try input_line ... with _ -> "unknown"` → `close_in` is risky because `close_in` is not in a `finally` block. If `input_line` raises, `ch` leaks. The `text` and CSV branches in `read_logged_node_value` and `read_standard_node_value` have been partially fixed to use `Fun.protect`, indicating this is a known pattern. This instance was missed.

  **Fix**: Apply the same `Fun.protect` pattern used elsewhere in the file:
  ```ocaml
  let ch = open_in class_path in
  let cls = Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
    try input_line ch |> String.trim with End_of_file -> "unknown"
  ) in
  ```
