# Review: src/arrow/arrow_io.ml

**Lines**: 426
**Severity summary**: 0 critical, 1 warning, 1 info

---

## WARNING: `int_of_string` / `float_of_string` without `_opt` variant

- **Line 135**: `int_of_string (String.trim s)` in `build_column` for `ArrowInt64`

  This is called after `infer_column_type` has validated all non-NA values, so it is safe by construction. However, if a future code path calls `build_column` with a type that was not inferred (e.g., from a user-specified schema), `int_of_string` will raise `Failure "int_of_string"` on invalid input.

  **Fix**: Use `int_of_string_opt` and fall back to `None` (or return an error result) if parsing fails.

- **Line 140**: `float_of_string (String.trim s)` in `build_column` for `ArrowFloat64`

  Same issue as above.

  **Fix**: Use `float_of_string_opt` for defensive parsing.

---

## WARNING: `raise exn` re-raise after cleanup (acceptable pattern)

- **Lines 296-297**: `with exn -> close_in_noerr ch; raise exn`

- **Lines 419-421**: `with exn -> close_out_noerr ch; raise exn`

  These re-raise exceptions after closing file handles. While this is a standard and correct pattern, the `read_csv_fallback` function (line 288) catches `Sys_error` but lets all other exceptions propagate uncaught to the caller. If `parse_csv_string` raises (e.g., from the `int_of_string` issue above), the exception will escape as a raw OCaml exception rather than a structured `VError`.

  **Fix**: Wrap the body of `read_csv_fallback` in a catch-all that converts exceptions to `Error msg` results, consistent with the rest of the IO API.

---

## INFO: `csv_quote_string` uses `sep.[0]` without empty-string guard

- **Line 365**: `String.contains s sep.[0]`

  The guard `String.length sep > 0 &&` prevents the unsafe access. However, if `sep` is empty, `csv_quote_string` will silently treat every string as unquoted (since `has_sep` evaluates to `false`). The `write_csv` function defaults to `sep=","` so this is not a practical concern, but it is a latent edge case.

  **Fix**: Add a guard at the top of `csv_quote_string` that defaults to `","` or returns early when `sep` is empty.
