# Review: src/packages/core/show_plot.ml

**Lines**: 787
**Severity summary**: 0 critical, 2 warning, 2 info

---

## WARNING: Catch-all exception handlers that swallow errors

- **Line 332**: `try ... with _ -> (try remove_path_recursively startup_path with _ -> ()); (try remove_path_recursively guard_root with _ -> ()))` — The outer `with _ ->` silently swallows any exception from `prepare_python_debug_guards` or `write_text_file`. If these fail, the user gets no feedback and the subshell may launch with misleading configuration.

  **Fix**: At minimum, `prerr_endline` a warning about the guard setup failure. Better yet, propagate the error or handle specific exceptions.

- **Line 377**: `with _ -> (try remove_path_recursively startup_path with _ -> ()); false` — Same pattern for Julia startup. Silently swallows write failures and sets `startup_ready = false`, which launches Julia without the guard.

  **Fix**: Same as above — print a warning.

## WARNING: Function `register` >80 lines

- **Lines 753–787**: The `register` function at 34 lines is fine, but the `show_plot_fn` closure inside it (lines 754–783) calls `resolve_plot_node`, `render_plot_artifact`, and `call_pipeline_to_mermaid` — each of which is non-trivial. The function itself is a thin dispatch.

  **Fix**: Minor — no action needed since the dispatch is clean.

## INFO: Child process IPC with pipe

- **Lines 162–212**: The `open_rendered_plot` function uses a pipe between forked child and parent to communicate launch success/failure. The child sends `"OK"` or an error string. The parent reads up to 256 bytes. If the child message is longer than 256 bytes, it would be truncated, potentially hiding error details.

  **Fix**: Either increase the buffer size or use a protocol with a length prefix.

## INFO: Unused `unwrap:false` in registration

- **Line 786**: `make_builtin_named ~name:"show_plot" ~unwrap:false 1 show_plot_fn` — The `show_plot_fn` signature is `named_args -> env -> value` but it only matches `[(_, plot)]` (single positional/named arg). With `~unwrap:false`, the named_args are passed as-is, but the function doesn't use named-arg dispatch.

  **Fix**: This is intentional — `~unwrap:false` is conservative. Consider that future versions may add named args.
