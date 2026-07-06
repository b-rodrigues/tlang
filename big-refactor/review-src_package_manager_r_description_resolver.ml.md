# Review: src/package_manager/r_description_resolver.ml

**Lines**: 354
**Severity summary**: 2 critical, 2 warning, 2 info

---

## CRITICAL: `String.sub` with negative length on empty `import()` / `importFrom()` call

- **Line 103**: `let inner = String.sub trimmed 7 (String.length trimmed - 8) in`
  If `trimmed = "import("` (exactly 7 characters), `starts_with ~prefix:"import("` is true, then `String.length trimmed - 8 = -1`, which raises `Invalid_argument ""`.

  **Fix**: Guard with `String.length trimmed > 7` before extracting, or use `String.sub` only when `String.length trimmed >= 8`.

- **Line 126**: `let inner = String.sub trimmed 11 (String.length trimmed - 12) in`
  If `trimmed = "importFrom("` (exactly 11 characters), `starts_with ~prefix:"importFrom("` is true, then `String.length trimmed - 12 = -1`, which raises `Invalid_argument ""`.

  **Fix**: Guard with `String.length trimmed > 11` before extracting, or use `String.sub` only when `String.length trimmed >= 12`.

---

## CRITICAL: Catch-all exception handlers that hide real errors

- **Line 176**: `let n = try Unix.read pipe_out_read buf 0 (Bytes.length buf) with _ -> 0 in`
  A catch-all `with _ ->` here masks any error from `Unix.read` (e.g., bad file descriptor, signal interruption) as "zero bytes read, EOF". If `pipe_out_read` becomes invalid mid-processing, the code silently enters an infinite loop (since `eof_out` is never set to `true`).

  **Fix**: Catch only `Unix.Unix_error (Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR, _, _)` and let other errors propagate or be logged.

- **Line 264**: `let entries = try Some (Sys.readdir path) with _ -> None in`
  Catch-all masks `Sys_error` (permission denied, not a directory) as `None`. This silently skips search in a directory that should be readable.

  **Fix**: Catch `Sys_error _` specifically, or convert to a logged warning.

---

## WARNING: Hard-coded 300-second timeout is a magic number

- **Line 161–163**: `if elapsed > 300.0 then (... Error "process timed out after 300 seconds" ...)`
  The 300-second timeout is hard-coded. Callers have no way to configure or override it.

  **Fix**: Make the timeout a parameter (with default `300.0`) on `run_git`, or define a module-level constant `let git_timeout = 300.0`.

---

## WARNING: Continuation line in `parse_dcf_content` silently dropped when no prior key exists

- **Line 22**: `| [] -> gather keys rest` — if a continuation line (starting with space/tab) appears before any key-value pair has been parsed, the line data is silently dropped. This is a data-loss bug for malformed DCF files.

  **Fix**: Accumulate a "pending continuation" segment and emit a warning, or treat leading continuation lines as ignored whitespace (which is technically valid DCF — leading whitespace before the first key on line 1 is ignored).

---

## INFO: Repetitive binary check pattern for `julia`

- **Line 143**: `run_git` could benefit from extracting the process-spawning logic into a reusable helper. The pattern of pipe setup, select loop, waitpid is duplicated compared to similar code elsewhere in the codebase.

  **Fix**: Create a `Process_helper` module with `run_process ~timeout ~argv` that returns `(stdout, stderr, status)` as a `result`.

---

## INFO: `find_file_recursively` returns first match via mutable `ref` — could be pure

- **Lines 268–277**: The `search` function uses a mutable `ref` cell to track the first found file, and uses `Array.iter` with side effects. This works but is non-idiomatic OCaml.

  **Fix**: Use an exception-based early return (`try ... with Found p -> p`) or convert to a tail-recursive function over a queue of directories.
