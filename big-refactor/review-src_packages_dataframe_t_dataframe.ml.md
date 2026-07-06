# Review: src/packages/dataframe/t_dataframe.ml

**Lines**: 253
**Severity summary**: 0 critical, 2 warnings, 1 info

---

## WARNING: Unvalidated `List.nth` calls in row-wise DataFrame construction

- **Line 77**: `List.nth rows i` inside `Array.init nrows (fun i -> ...)`. `nrows = List.length rows`, so `i` is always in bounds. However, if `rows` is mutated or the `nrows` derivation changes, this will raise `Failure "nth"`.

  **Fix**: Convert `rows` to an array once with `Array.of_list rows` and use array indexing `rows_arr.(i)` throughout.

- **Line 100**: Same pattern — `List.nth rows i` in the `VList` row case.

  **Fix**: Same as above.

---

## WARNING: Raw `Failure` exception in to_dataframe column validation

- **Line 48**: `raise (Failure (Printf.sprintf "column `%s` length %d does not match max length %d" ...))`. This is caught by the enclosing `try ... with Failure msg ->` at line 33, so it's converted to `Error.value_error`. Per AGENTS.md rule #3 ("No raw OCaml exceptions in user-facing paths"), this should return `VError` directly instead of raising.

  **Fix**: Replace the `if ... then raise (Failure ...)` with a `Result` flow:
  ```ocaml
  let check_column_length name vec nrows =
    if Array.length vec = 1 && nrows > 1 then Ok (name, Array.make nrows vec.(0))
    else if Array.length vec <> nrows && (nrows > 0 || Array.length vec > 0) then
      Error (Error.value_error (Printf.sprintf "column `%s` ..." name))
    else Ok (name, vec)
  in
  (* collect results, short-circuit on first error *)
  ```
  Then remove the enclosing `try/with`.

---

## INFO: Unused variable `_ncols`

- **Line 71**: `let _ncols = List.length headers in` — underscore-prefixed, explicitly acknowledged as unused. This is fine, but the variable serves no purpose.
- **Line 94**: Same pattern.

  **Fix**: Remove both bindings. They are never referenced (even the underscore prefix indicates dead intent).
