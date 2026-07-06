# Review: src/packages/pipeline/read_node.ml

**Lines**: 714
**Severity summary**: 0 critical, 2 warning, 2 info

---

## WARNING: Catch-all exception handlers in guard setup

- **Lines 332–334**: `try ... with _ -> (try remove_path_recursively startup_path with _ -> ()); (try remove_path_recursively guard_root with _ -> ()))` — If `prepare_python_debug_guards` or `write_text_file` fail (e.g., disk full, permissions), the exception is silently swallowed and the subshell launches without the Python package manager guards. The user has no indication that guards failed to install.

  **Fix**: Print a warning to stderr before swallowing.

- **Line 377**: `with _ -> (try remove_path_recursively startup_path with _ -> ()); false` — Same pattern for Julia startup. Silently falls back to `julia -i` without the guard.

  **Fix**: Same as above.

## WARNING: Long `run_interactive_subshell` function

- **Lines 214–404**: `run_interactive_subshell` is 190 lines long. It handles Python, R, and Julia debug REPL setup with environment variable preparation, dependency resolution, startup file writing, and guard installation. The three runtimes each have distinct setup code with significant repetition.

  **Fix**: Extract per-runtime setup into separate functions (`setup_python_debug`, `setup_r_debug`, `setup_julia_debug`) to reduce the function size and make the per-runtime logic independently testable.

## INFO: String.sub with proper bounds guard

- **Lines 488–489**: `if String.length name > 6 && String.sub name 0 6 = "<noop:" then ...` — Properly guards the `String.sub` call with a length check. No issue.

  **Fix**: No action needed.

- **Lines 609–610**: Same pattern for `inspect_fn`.

  **Fix**: No action needed.

## INFO: run_shell_command_with_env uses /bin/sh -c

- **Line 172**: `Unix.create_process_env "/bin/sh" [| "/bin/sh"; "-c"; shell_cmd |] envp ...` — The shell command string is passed directly to `sh -c`. The `shell_cmd` is constructed internally (fixed strings for python/R/Julia/bash) so there's no injection risk, but if this is ever extended to accept user input, it would be a vector.

  **Fix**: No action needed given current usage.
