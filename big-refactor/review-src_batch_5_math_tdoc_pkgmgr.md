# Review: src/packages/math/ (26 files), src/tdoc/ (5 files), src/package_manager/ (7 files)

**Source**: `/home/brodrigues/Documents/repos/tlang`

---

# Package: `src/packages/math/`

## `acos.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `acosh.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `asin.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `asinh.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `atan.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `atan2.ml` (81 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `atanh.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `ceiling.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `cos.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `cosh.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `floor.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `math_common.ml` (99 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `pow.ml` (91 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `round.ml` (53 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `signif.ml` (42 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `sign.ml` (18 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `sin.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `sinh.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `t_abs.ml` (51 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `tan.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `tanh.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `t_exp.ml` (50 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `t_iota.ml` (30 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `t_log.ml` (64 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `trunc.ml` (19 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `t_sqrt.ml` (64 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

# Package: `src/tdoc/`

## `tdoc_types.ml` (177 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `tdoc_parser.ml` (213 lines)

**Severity summary**: 1 critical, 1 warning, 0 info

---

### CRITICAL: `open_in` unguarded against `Sys_error`

- **Line 31**: `let chan = open_in filename in` in `extract_comments`. The `try...with` block on line 33 only catches `End_of_file`. If `filename` does not exist or is unreadable, `open_in` raises `Sys_error` which propagates uncaught through `parse_file`, a user-facing API entry point.

  **Fix**: Move `open_in` inside the `try` block, or add a `Sys_error` handler before line 31. Wrap the body of `extract_comments` (or `parse_file`) in a `try...with Sys_error msg -> ...` that returns a documented error value.

### WARNING: Dead code after infinite loop

- **Lines 34-36**: `while true do ... done; [] (* unreachable *)`. The empty list literal `[]` after the `while true` loop is dead code (the loop always exits via `End_of_file` exception). The comment acknowledges this.

  **Fix**: Remove the unreachable `[]` literal. Replace with `[]` in the `End_of_file` handler after `close_in chan` (it already returns `List.rev !lines`; the `[]` after `done` is never needed).

---

## `tdoc_registry.ml` (82 lines)

**Severity summary**: 1 critical, 2 warning, 0 info

---

### CRITICAL: `open_out` unguarded against `Sys_error`

- **Line 34**: `let chan = open_out filename in` in `to_json_file`. If the output path is unwritable, `open_out` raises `Sys_error` which propagates uncaught. This function is user-facing (documentation export).

  **Fix**: Wrap `open_out`...`close_out` in a `try...with Sys_error msg -> ...` block, or use `Fun.protect ~finally:(fun () -> close_out_noerr chan)` with a guard around `open_out`.

### WARNING: Global mutable state

- **Line 6**: `let registry : (string, doc_entry) Hashtbl.t = Hashtbl.create 100`. Module-level mutable `Hashtbl.t` state is a testing and thread-safety concern.

  **Fix**: Parameterise functions to accept and return the registry explicitly, or keep it module-local but document thread-safety constraints. The current design is acceptable for a single-threaded CLI tool but should be documented.

### WARNING: Catch-all exception handler

- **Lines 79-82**: `with | Sys_error msg -> ... | Tdoc_json.Json_error msg -> ... | exn -> Printf.eprintf ...`. The `| exn ->` catch-all silently swallows `Out_of_memory`, `Stack_overflow`, and other fatal exceptions, converting them into a printed warning.

  **Fix**: Re-raise `Out_of_memory` and `Stack_overflow` before the catch-all, or be more specific about expected exception types.

---

## `tdoc_json.ml` (82 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found. (Library-defined `Json_error` exception and re-raise from Yojson are part of this module's intentional API design.)

---

## `tdoc_markdown.ml` (140 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

# Package: `src/package_manager/`

## `documentation_manager.ml` (41 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `package_loader.ml` (291 lines)

**Severity summary**: 0 critical, 1 warning, 0 info

---

### WARNING: Catch-all `with _ ->` silently swallows exceptions

- **Line 76**: `with _ -> []` in `load_private_names`. If `Tdoc_registry.load_from_json` raises any exception (including `Sys_error` from a missing file, `Out_of_memory`, `Stack_overflow`, `Json_error`, etc.), all are silently swallowed and an empty list is returned. The `Sys.file_exists` guard on line 68 reduces the risk, but does not eliminate it (e.g., race conditions, corrupt JSON).

  **Fix**: Match specific expected exceptions (`Sys_error`, `Tdoc_json.Json_error`) and only catch those. Re-raise `Out_of_memory` / `Stack_overflow`. Log unexpected errors.

---

## `package_types.ml` (150 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `release_manager.ml` (225 lines)

**Severity summary**: 0 critical, 2 warning, 0 info

---

### WARNING: Catch-all exception handler in `run_command`

- **Line 65**: `with e -> Error (Printexc.to_string e)`. The `run_command` function catches all exceptions, including `Out_of_memory`, `Stack_overflow`, `Invalid_argument`, etc.

  **Fix**: Match specific exceptions (`Unix.Unix_error`, `Sys_error`) and re-raise fatal ones. Consider using `Fun.protect` for resource cleanup.

### WARNING: Catch-all exception handler in `run_command_argv`

- **Line 123**: `with e -> Error (Printexc.to_string e)`. Same pattern as `run_command` — catches all exceptions, including fatal ones.

  **Fix**: Same as above — be specific about caught exception types.

---

## `renv_resolver.ml` (190 lines)

**Severity summary**: 0 critical, 1 warning, 0 info

---

### WARNING: Catch-all exception handler

- **Line 28**: `with exn -> Error (Printf.sprintf "Failed to read renv.lock: %s" (Printexc.to_string exn))`. Catches all exceptions from `open_in`, `really_input_string`, and `close_in`. Fatal exceptions like `Out_of_memory` and `Stack_overflow` are caught and converted to an `Error` string.

  **Fix**: Match `Sys_error` specifically for file I/O errors. Re-raise `Out_of_memory` and `Stack_overflow`.

---

## `template_engine.ml` (60 lines)

**Severity summary**: 0 critical, 0 warning, 0 info

No issues found.

---

## `test_discovery.ml` (217 lines)

**Severity summary**: 0 critical, 2 warning, 0 info

---

### WARNING: Catch-all silently swallows all exceptions in `run_test_file`

- **Lines 98-99**: `| Out_of_memory | Stack_overflow as exn -> raise exn | _ -> env`. While this correctly re-raises OOM/stack overflow, all other exceptions (syntax errors, parse errors, type errors, runtime errors in src files) are silently swallowed and the environment is returned unchanged. This could mask real bugs in test source files.

  **Fix**: Log the exception (at least at a debug level) before returning `env`, or allow the exception to propagate to the outer `try...with` handler on line 147 which already handles these cases.

### WARNING: Catch-all exception handler in `run_test_file` outer try

- **Lines 147-151**: `| exn -> ... { ... error_msg = Some (Printf.sprintf "Unexpected: %s" (Printexc.to_string exn)); ... }`. Catches all exceptions including fatal ones, converting them to a test failure instead of crashing.

  **Fix**: Re-raise `Out_of_memory` and `Stack_overflow` before the catch-all.
