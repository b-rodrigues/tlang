# Review: src/package_manager/nix_generator.ml

**Lines**: 672
**Severity summary**: 1 critical, 0 warning, 2 info

---

## CRITICAL: Uncaught I/O exceptions in `install_flake` break `result` contract

- **Lines 653–670**: The function `install_flake` declares a return type of `(string, string) result` (line 624), but its `else` branch (non-dry-run path at line 651) performs `open_in`, `open_out`, `really_input_string`, and `output_string` without any `try/with` block. Each of these can raise `Sys_error`. If any fails (e.g., disk full, permissions error, missing directory), the exception propagates uncaught out of the function, bypassing the `result` type.

  The specific vulnerable sites:
  - Line 655: `let ch = open_in flake_path in` — raises `Sys_error` if file is unreadable.
  - Line 659: `really_input_string ch (in_channel_length ch)` — raises `Sys_error` on I/O error.
  - Line 661: `let ch_out = open_out bak in` — raises `Sys_error` if backup cannot be created.
  - Line 667: `let ch = open_out flake_path in` — raises `Sys_error` if flake.nix cannot be written.

  **Fix**: Wrap the I/O operations in a `try/with` that catches `Sys_error` and returns `Error msg`, consistent with the function's type signature. Example:
  ```ocaml
  | Ok _ -> ...
  | Error msg -> Error msg
  ```
  becomes:
  ```ocaml
  | Ok _ ->
      (try ... with Sys_error e -> Error e)
  | Error msg -> Error msg
  ```

---

## INFO: Dead `Error` match arms on `git_url_to_flake_input`

- **Lines 240, 491**: The pattern `| Error _ -> ()` in `List.iter (fun dep -> match git_url_to_flake_input dep with ...)` is dead code. Function `git_url_to_flake_input` (line 106) never returns `Error` — every code path produces `Ok`. The final `| None ->` at line 130 returns `Ok (Printf.sprintf ...)` unconditionally. This is harmless but confusing and should be removed or changed to a wildcard to document intent:

  ```ocaml
  | _ -> ()
  ```

---

## INFO: Hardcoded version string

- **Line 6**: `let companion_package_version = "0.1.0"` is a magic string buried at the top level. It is not referenced anywhere in this file (or apparently used at all). If it is dead code, remove it. If it is a legitimate constant, consider lifting it to a config module or documenting its purpose and consumer.
