# Review: src/repl.ml

**Lines**: 1425
**Severity summary**: 0 critical, 5 warning, 3 info

---

## WARNING: `levenshtein_distance` function duplicated from `src/ast.ml`

- **Lines 245-260**: This is a byte-for-byte duplicate of `levenshtein` in `src/ast.ml` (lines 1144-1160). Two implementations increase maintenance burden and risk of divergence.

  ```ocaml
  let levenshtein_distance s t =
    let m = String.length s and n = String.length t in
    ...
  ```

  **Fix**: Use `Ast.levenshtein` instead of redefining.

---

## WARNING: `source_location` function duplicated from `src/eval.ml`

- **Lines 21-26**: Identical to `source_location` in `src/eval.ml` (lines 252-257).

  **Fix**: Expose `source_location` from `Eval` or move to a shared module.

---

## WARNING: `handle_magic` function too long with deeply nested conditionals

- **Lines 387-492**: The `handle_magic` function handles 10+ magic commands (`%time`, `%ls`, `%pwd`, `%cd`, `%env`, `%history`, `%objects`, `%magic`, `%reset`, `%save`) in a single match expression. The `%cd` branch (lines 405-416) contains additional nested conditionals for tilde expansion. Consider splitting each magic command into its own handler function.

---

## WARNING: `cmd_repl` function too long (~200 lines) and deeply nested

- **Lines 973-1162**: The main REPL loop contains the multi-line input reader, command dispatch (`:quit`, `:help`, `:version`, `:packages`, `:complete`), magic command handling, and completion callbacks. The `read_multiline` inner function (lines 1118-1143) adds additional nesting depth.

  **Fix**: Extract the REPL command dispatcher and multi-line input logic into separate functions.

---

## WARNING: `recursive_files` uses catch-all exception handler that may hide errors

- **Line 835**: `Sys.readdir d` is wrapped in `try ... with _ -> [||]`, which catches all exceptions. If the directory exists but is unreadable, this silently returns an empty list instead of reporting the error.

  ```ocaml
  let entries = try Sys.readdir d with _ -> [||] in
  ```

  **Fix**: Catch specific exceptions (e.g., `Sys_error _`) instead of using `with _ ->`.

---

## INFO: `write_vars_csv` has a catch-all `with _ ->` handler

- **Lines 968-969**: The outer try block catches all exceptions silently:

  ```ocaml
  with _ ->
    begin try Sys.remove tmp_path with _ -> () end
  ```

  This could silently swallow I/O errors when writing the Atelier variable CSV, making debugging difficult.

  **Fix**: At minimum log the error, or handle specific exceptions.

---

## INFO: `run_file` function uses `really_input_string` without checking file size first

- **Line 69**: `really_input_string ch (in_channel_length ch)` loads the entire file into memory. For very large files this could cause memory issues, but is acceptable for a scripting language interpreter.

---

## INFO: `cmd_doc` function opens files without explicit encoding handling

- **Lines 844-862**: File I/O in `cmd_doc` does not specify encoding (assumes system default). While acceptable on most platforms, this could cause issues on Windows or with non-UTF-8 file names.
