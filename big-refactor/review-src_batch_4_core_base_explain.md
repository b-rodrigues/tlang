# Review: src/packages/core/args.ml

**Lines**: 61
**Severity summary**: 0 critical, 0 warning, 1 info

---

## INFO: `List.map2` raises on length mismatch

- **Line 28**: `List.map2` on `display_names` and `l.param_types`. Both lists originate from the same `VLambda`, so in practice they should match, but `List.map2` raises `Invalid_argument` on any length mismatch. A safer alternative is `List.map2_exn` or manual `List.combine` + `map` with explicit error handling.

  **Fix**: Replace with `List.combine` wrapped in a `try/with` that returns `VError`, or assert lengths match before calling `List.map2`.

---

# Review: src/packages/core/file_ops.ml

**Lines**: 210
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Catch-all exception handler in `read_file`

- **Line 113-114**: `| exn -> Error.make_error FileError (Printf.sprintf "read_file: %s" (Printexc.to_string exn))` swallows all exceptions (including `Invalid_argument`, `Failure`, etc.) and converts them to generic `FileError`. While `Sys_error` is handled separately above, any unexpected exception (e.g., from `in_channel_length`, `Bytes.create`, `really_input`) is silently downgraded.

  **Fix**: Either handle specific exception types explicitly or add a comment explaining why a catch-all is safe here (e.g., all possible exceptions from file I/O are genuinely file-related).

---

# Review: src/packages/core/head.ml

**Lines**: 67
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/core/help.ml

**Lines**: 154
**Severity summary**: 0 critical, 1 warning, 1 info

---

## WARNING: Catch-all exception handler in `contains` helper

- **Line 124**: `with _ -> false` in the local `contains` helper suppresses every exception (e.g., `Invalid_argument` from `String.sub` if indices are miscalculated). While functionally safe (returns `false` on unexpected errors), it silently hides logic bugs.

  **Fix**: Restructure the `contains` function to use `String.sub` with explicit bounds checks rather than relying on try/with, or replace with `String.starts_with`/`String.slice` (OCaml 4.13+ utilities) or `Str.string_match`.

## INFO: Physical equality (`==`) for lambda lookup

- **Line 75**: `k_val == lam` uses `==` (physical equality) to find a lambda value in the environment by identity. This is intentional for closure matching but is fragile — two syntactically identical lambdas will not match. Document this assumption.

  **Fix**: Add a comment explaining why `==` is used (identity comparison for closure lookup) and note that this will fail for re-parsed or deserialized lambdas.

---

# Review: src/packages/core/is_error.ml

**Lines**: 25
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/core/path_ops.ml

**Lines**: 180
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/core/sum.ml

**Lines**: 86
**Severity summary**: 0 critical, 1 warning, 0 info

---

## WARNING: Mutable state with `ref` where functional style is possible

- **Lines 50-54**: Uses `total_int`, `total_float`, `is_float`, `type_error`, `na_error_triggered`, `na_count` as mutable `ref` cells in an imperative `for` loop over the array. This could be replaced with a single `Array.fold_left` that accumulates a variant type, eliminating all mutable state.

  **Fix**:
  ```ocaml
  let init = SumInt 0 in
  let result = Array.fold_left (fun acc v -> ...) init arr in
  ```
  where `SumInt`, `SumFloat`, `SumError`, `SumNA` etc. are variants in an accumulator type.

---

# Review: src/packages/core/tail.ml

**Lines**: 77
**Severity summary**: 0 critical, 0 warning, 1 info

---

## INFO: Inconsistent default behavior between DataFrame and List/Vector

- **Lines 44, 54, 66**: `tail(df)` defaults to returning the last 5 rows, while `tail(list)` and `tail(vec)` without `n` default to dropping the first element (last n-1 items). R's `tail()` consistently returns the last 6 items by default for all types. This inconsistency may surprise users.

  **Fix**: Make all overloads default to returning the last 5 (or 6) elements consistently.

---

# Review: src/packages/core/t_float_seq.ml

**Lines**: 56
**Severity summary**: 0 critical, 0 warning, 1 info

---

## INFO: `raise (Failure ...)` in `as_float`/`as_int` helpers

- **Lines 31, 38**: `raise (Failure "...")` in `as_float` and `as_int` helper functions. These are caught by the enclosing `try...with Failure msg ->` on line 54, so no exception escapes to the user. However, the pattern breaks the "no raw OCaml exceptions in user-facing paths" convention.

  **Fix**: Make `as_float`/`as_int` return `(float, value) result` or `(int, value) result` and propagate via `match` instead of exceptions.

---

# Review: src/packages/core/t_map.ml

**Lines**: 35
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/core/t_pattern.ml

**Lines**: 16
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/core/t_print.ml

**Lines**: 75
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/core/t_seq.ml

**Lines**: 73
**Severity summary**: 0 critical, 0 warning, 1 info

---

## INFO: `raise (Failure ...)` in `as_int` helper

- **Line 30**: `raise (Failure "...")` in `as_int` helper. Same pattern as `t_float_seq.ml` — caught by `try...with Failure msg ->` on line 71, so no exception escapes. Convention requires returning `VError` instead of raising.

  **Fix**: Make `as_int` return `(int, value) result` and propagate with `match`.

---

# Review: src/packages/core/t_type.ml

**Lines**: 27
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/core/t_write_text.ml

**Lines**: 35
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/base/deserialize.ml

**Lines**: 26
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/base/error_mod.ml

**Lines**: 46
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/base/error_utils.ml

**Lines**: 249
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/base/fetchurl.ml

**Lines**: 97
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/base/is_na.ml

**Lines**: 28
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/base/na.ml

**Lines**: 74
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/base/prefetch.ml

**Lines**: 59
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/base/sample.ml

**Lines**: 74
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/base/serialize.ml

**Lines**: 28
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/base/set_seed.ml

**Lines**: 27
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/base/t_json.ml

**Lines**: 52
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/explain/explain_json.ml

**Lines**: 29
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/explain/intent_fields.ml

**Lines**: 24
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.

---

# Review: src/packages/explain/intent_get.ml

**Lines**: 28
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found.
