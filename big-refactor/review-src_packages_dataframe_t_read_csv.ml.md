# Review: src/packages/dataframe/t_read_csv.ml

**Lines**: 234
**Severity summary**: 0 critical, 1 warning, 1 info

---

## WARNING: `failwith` in URL download path

- **Line 223**: `failwith msg` is called inside the URL download error path (`Arrow_io.download_url` returning `Error`). While this is caught by the outer `try ... with e -> Error.make_error FileError (Printexc.to_string e)` at line 228, it violates AGENTS.md rule #3 ("No raw OCaml exceptions in user-facing paths"). The pattern also loses the structured nature of the original error — `Printexc.to_string` stringifies it, turning it into an opaque message.

  **Fix**: Thread the `Error` result directly instead of converting to an exception:
  ```ocaml
  | Error msg ->
      Error.make_error FileError (Printf.sprintf "Failed to download URL: %s" msg)
  ```
  And restructure the I/O flow to use `Result.bind` instead of try/with.

---

## INFO: `List.nth` with bounds guard (safe but fragile)

- **Line 132**: `List.nth row col_idx`. The row is from `valid_rows` (filtered to only include rows with `List.length row = ncols`), and `col_idx` ranges from 0 to `ncols - 1` via `List.mapi`. So this is safe by construction. But `List.nth` is O(n) and the safety depends on a non-local invariant.

  **Fix**: Since `valid_rows` is immediately converted to an array via `Array.of_list` at line 127, consider using `rows_arr.(row_idx).(col_idx)` if the rows were also arrays. Alternatively, keep as-is but add a comment noting the safety invariant.

No other issues found. The CSV parsing logic is well-structured with explicit state management, proper `--#` docstrings, and consistent error handling.
