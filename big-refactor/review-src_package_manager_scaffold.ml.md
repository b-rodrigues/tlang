# Review: src/package_manager/scaffold.ml

**Lines**: 1017
**Severity summary**: 0 critical, 1 warning, 1 info

---

## WARNING: Catch-all exception handler in `copy_text_file` swallows details

- **Lines 57–72**: The entire body of `copy_text_file` is wrapped in a catch-all handler:

  ```ocaml
  with exn ->
    Printf.eprintf "Warning: Could not copy '%s' to '%s': %s\n"
      src_path dest_path (Printexc.to_string exn);
    false
  ```

  While the error is logged to stderr, the catch-all prevents the caller from distinguishing between different failure modes (e.g., permission denied vs. source not found vs. disk full). If a caller of `copy_text_file` (e.g., `copy_agent_files` at line 105 or `copy_skill_file` at line 154, `write_project_pipeline` at line 838) needs to react differently, they cannot.

  **Fix**: Only catch specific exceptions that are expected (`Sys_error`, `Unix_error`) and let unexpected exceptions propagate. Alternatively, if catch-all is truly intentional for this utility, document why with a comment.

---

## INFO: `Sys.argv.(0)` access without bounds check

- **Line 40**: `Filename.dirname (Filename.dirname (Sys.argv.(0)))` accesses `Sys.argv` at index 0 without a bounds check.

  This is a universal OCaml idiom and will never fail in a correctly-invoked compiled binary (the runtime always sets `Sys.argv.(0)`). However, under unusual testing setups where `Sys.argv` could be `[||]`, this would raise `Invalid_argument`. Consider adding a fallback for defensive safety:

  ```ocaml
  let self_dir = if Array.length Sys.argv > 0 then Filename.dirname Sys.argv.(0) else "" in
  ```
