# Review: `src/pipeline/builder_utils.ml`

**Lines**: 573
**Severity summary**: 1 critical, 4 warnings, 2 info

---

## CRITICAL: `String.sub` Potential out-of-bounds in `eval_node_store_path`

- **Line 567-571**: `eval_node_store_path` strips surrounding double quotes from `nix-instantiate --json` output:
  ```ocaml
  let clean =
    if len >= 2 && res.[0] = '"' && res.[len - 1] = '"' then
      String.sub res 1 (len - 2)
    else
      res
  in
  ```
  The guard `len >= 2` AND `res.[0] = '"' && res.[len - 1] = '"'` is interchangeable when `len = 1`: then `res.[0] = res.[len - 1]`, so a 1-character string `"\""` would pass the guard, and `String.sub res 1 (1 - 2) = String.sub res 1 (-1)` raises `Invalid_argument`.

  In practice, `nix-instantiate --json` never returns a bare `"` for a store path, so this is unlikely to trigger in normal use. However, it is a latent crash if `nix-instantiate` ever returns unexpected output (e.g., an error message that is the single character `"`).

  **Fix**: Add `len >= 2 &&` before doing the substring, or use a safer approach:
  ```ocaml
  if len >= 2 && res.[0] = '"' && res.[len - 1] = '"' then
    String.sub res 1 (max 0 (len - 2))
  else
    res
  ```

---

## WARNING: Function Too Long — `validate_nix_options`

- **Line 42-180**: `validate_nix_options` is ~138 lines. It validates all 9 options by repeating the same pattern 9 times. This is verbose but structurally consistent.

  **Fix**: Extract per-option validation into a helper function or a list-driven fold.

## WARNING: Function Too Long — `run_command_stream` & `run_command_stream_argv`

- **Line 207-293**: `run_command_stream` is ~86 lines. Contains duplicated I/O multiplexing logic (select loop, byte processing, line buffering).
- **Line 298-384**: `run_command_stream_argv` is ~86 lines. Nearly identical code body to `run_command_stream` except for the process-spawning call.

  **Fix**: Extract the shared I/O multiplexing core into a helper, parameterized by the process handle.

## WARNING: Catch-all Exception Handler in `read_file_first_line`

- **Line 202**: `with _ -> None` — masks all exceptions from file opening/reading, including `Sys_error` for permission-denied files and `Invalid_argument` for problematic paths.

  **Fix**: Use a more specific exception handler (e.g., `with Sys_error _ -> None | End_of_file -> None`), or propagate the error as a `result` type.

## WARNING: Use of Deprecated `Unix.open_process_full` with Shell Expansion

- **Line 209**: `run_command_stream` uses `Unix.open_process_full cmd (Unix.environment ())` which passes the command through `/bin/sh`. This is a shell-injection risk if `cmd` contains user-controlled content. The sibling function `run_command_stream_argv` (line 303) correctly uses `Unix.open_process_args_full` which bypasses the shell.

  **Fix**: If `run_command_stream` is used only with hardcoded commands, add a comment documenting that. Otherwise, migrate callers to `run_command_stream_argv`.

## INFO: Dead Code — `run_command_capture`

- **Line 386-390**: `run_command_capture` is defined but never used within this module. It wraps `run_command_stream` in a capture pattern. It may be used by other modules, but having it alongside the more ergonomic `run_command_argv_capture` (line 422) suggests it may be vestigial.

  **Fix**: Remove if unused across the entire codebase.

## INFO: Unused Module Open

- **Line 43**: `let open Ast in` is used only for the `VNA` constructor reference on line 50. In a 138-line function, the open is scoped tightly enough, but the `Ast.` prefix is used nowhere else in the function — the single reference `VNA NAGeneric` on line 50 is the only place `Ast` items are used without prefix.

  **Fix**: Replace `VNA NAGeneric` with `Ast.VNA Ast.NAGeneric` and remove the `open Ast` to be explicit about where `NAGeneric` comes from.
