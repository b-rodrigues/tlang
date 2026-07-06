# Package Manager Source Review (batch 7/7)

---

# Review: src/package_manager/documentation_manager.ml

No issues found.

---

# Review: src/package_manager/package_loader.ml

- **WARNING (IO leak, line 121–123)**: File handle opened with `open_in` is not guarded by `Fun.protect`. If `really_input_string` or `in_channel_length` raises an exception (e.g. `Sys_error`, `End_of_file`), `close_in` is skipped and the file handle leaks. The outer exception handlers (`Lexer.SyntaxError`, `Parser.Error`, `Sys_error`) might catch some failures but not all (e.g. `Out_of_memory`, `End_of_file` from oversized file). Prefer:
  ```ocaml
  let ch = open_in file in
  Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
    let content = really_input_string ch (in_channel_length ch) in ...)
  ```

- **WARNING (catch-all, line 76)**: `with _ -> []` in `load_private_names` silently swallows *all* exceptions from `Tdoc_registry.load_from_json` / `Tdoc_registry.get_all`. This could mask genuine programming errors (e.g. type mismatches in `doc_entry`) as "no private names", leading to non-obvious import behavior. Narrow to expected exceptions or log the error.

---

# Review: src/package_manager/package_types.ml

No issues found.

---

# Review: src/package_manager/release_manager.ml

- **WARNING (process leak, lines 9–65)**: `run_command` opens a subprocess via `Unix.open_process_full` but does not guard cleanup with `Fun.protect`. If `drain` (line 22) raises an exception (e.g. `Sys_error` on `input`, `Out_of_memory`), the `close_out` / `Unix.close_process_full` calls never execute and the child process leaks. The catch-all `with e ->` on line 65 catches the exception but does not close the handles. Wrap the body in `Fun.protect ~finally:(fun () -> ...)`.

- **WARNING (process leak, lines 69–123)**: Identical pattern to `run_command` in `run_command_argv`. Same fix needed.

- **WARNING (catch-all, line 65)**: `with e -> Error (Printexc.to_string e)` converts all OCaml exceptions (including programming errors like `Match_failure`, `Invalid_argument`) into `Error` results. Prefer catching only declared/expected exceptions; let fatal bugs propagate as unhandled exceptions during development.

- **WARNING (catch-all, line 123)**: Same catch-all pattern as line 65 in `run_command_argv`. Same concern.

---

# Review: src/package_manager/renv_resolver.ml

- **WARNING (function length, lines 90–179)**: `split_packages` is 89 lines — exceeds the 80-line guideline. It handles three distinct concerns in one function: package classification (CRAN vs Git vs unsupported), remote URL construction, and recursive remotes resolution. Refactor into named sub-functions.

- **WARNING (mutable state, lines 96–98)**: `split_packages` accumulates results in three `ref` cells (`cran_pkgs`, `git_pkgs`, `unsupported`) with imperative `List.iter`. Prefer a functional fold (e.g. `List.fold_left` over `parsed_packages` returning a record/triple) to avoid accidental aliasing and improve composability.

- **INFO (style, line 33)**: `get_string` uses `try List.assoc ... with Not_found ->` instead of the standard library's `List.assoc_opt`. Not unsafe, but `List.assoc_opt` is cleaner and avoids the `try/with` overhead.

- **INFO (missing docstrings)**: `is_base_r_package`, `get_string`, `get_string_value`, `get_string_list`, `parse_renv_lock_json`, `sanitize_remote_string`, `read_and_split_cran_packages`, and `read_and_split_git_packages` lack `(** ... *)` docstrings. Several are internal helpers but `read_and_split_*` are public interface functions.

---

# Review: src/package_manager/template_engine.ml

No issues found.

---

# Review: src/package_manager/test_discovery.ml

- **WARNING (function length, lines 56–151)**: `run_test_file` is 95 lines — exceeds the 80-line guideline. It handles file reading, environment setup, package source pre-loading, statement evaluation, and error aggregation. Extract the source-preloading logic (lines 68–103) and the statement-runner loop (lines 108–122) into separate helper functions.

- **WARNING (catch-all, line 99)**: `| _ -> env` in the source-file pre-loading loop silently swallows *all* exceptions (parse errors, evaluation errors, etc.) and continues. This can mask broken `src/` files during test runs, leading to confusing failures (tests pass against a silently broken environment). At minimum, log the suppressed error.
