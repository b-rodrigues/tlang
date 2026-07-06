# Review: src/package_manager/update_manager.ml

**Lines**: 903
**Severity summary**: 0 critical, 2 warnings, 1 info

---

## WARNING: Catch-all exception handler in `run_git_ls_remote_tags`

- **Line 373**: The `with _ -> Error "git ls-remote invocation failed"` at the end of `run_git_ls_remote_tags` catches every possible exception (`Unix_error`, `Sys_error`, `Invalid_argument`, `Match_failure`, etc.) and maps them all to the same generic string. This makes debugging difficult: "git ls-remote invocation failed" could mean git is not installed, the remote URL is unreachable, an environment variable is corrupt, or a pattern match inside the function failed.

  **Fix**: Narrow the handler to only the expected exception types (`Unix_error` and `Sys_error`), or propagate a more descriptive message using `Printexc.to_string`:

  ```ocaml
  with exn -> Error (Printf.sprintf "git ls-remote invocation failed: %s" (Printexc.to_string exn))
  ```

---

## WARNING: `read_file` leaks channel on partial read failure

- **Lines 35–41**: `read_file` opens a channel, reads its content, then closes it — but the `close_in` call is **not** guarded by `Fun.protect`:

  ```ocaml
  let ch = open_in path in
  let content = really_input_string ch (in_channel_length ch) in
  close_in ch;
  Ok content
  ```

  If `really_input_string` raises `Sys_error` partway through (e.g., device error on a network filesystem), `close_in ch` is never reached and the file descriptor leaks. The file descriptor will only be reclaimed by the GC when `ch` is finalized.

  **Fix**: Use `Fun.protect ~finally` to ensure the channel is always closed:

  ```ocaml
  let ch = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ch)
    (fun () ->
      let content = really_input_string ch (in_channel_length ch) in
      Ok content)
  ```

---

## INFO: Misleading error message in `cmd_upgrade` catch-all

- **Line 902**: The catch-all handler in `cmd_upgrade` reads:

  ```ocaml
  with e -> Error (Printf.sprintf "Failed to update tproject.toml: %s" (Printexc.to_string e))
  ```

  However, the `try` block at line 894 covers both the `open_out`/`output_string` call (which writes `tproject.toml`) AND the `update_flake_lock ()` call at line 901. If `update_flake_lock` fails (e.g., a Nix build error), the logged message will incorrectly claim the failure was in `tproject.toml` update, misleading the user.

  **Fix**: Separate the two operations into distinct `try/with` blocks with accurate messages, or restructure so that the `tproject.toml` write is confirmed before `update_flake_lock` is called, and the outer handler only catches TOML-write errors.
