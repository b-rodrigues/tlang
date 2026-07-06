# Verification Report: src/arrow/arrow_io.ml

## File: src/arrow/arrow_io.ml

### Finding: `int_of_string` without `_opt` (Original line: 135)

**Actual line**: 135
**Status**: CONFIRMED

**Evidence**:
```
133:       Arrow_table.IntColumn (Array.map (fun s ->
134:         if is_na_string s then None
135:         else Some (int_of_string (String.trim s))
136:       ) values)
```
**Verdict**: Exact match. `int_of_string` raises `Failure "int_of_string"` on invalid input. The review correctly notes this is safe by construction (called after `infer_column_type` which validates via `int_of_string_opt`), but fragile if called from a path that doesn't pre-validate.

---

### Finding: `float_of_string` without `_opt` (Original line: 140)

**Actual line**: 140
**Status**: CONFIRMED

**Evidence**:
```
138:       Arrow_table.FloatColumn (Array.map (fun s ->
139:         if is_na_string s then None
140:         else Some (float_of_string (String.trim s))
141:       ) values)
```
**Verdict**: Exact match. Same issue as above — `float_of_string` raises on invalid input. Safe by construction (pre-validated by `infer_column_type`) but fragile.

---

### Finding: `raise exn` re-raise after cleanup (Original lines: 296-297)

**Actual lines**: 295-297
**Status**: CONFIRMED

**Evidence**:
```
295:       with exn ->
296:         close_in_noerr ch;
297:         raise exn
```
**Verdict**: Exact match. The `raise exn` pattern is a standard and correct cleanup pattern. The review notes this is correct but warns that `read_csv_fallback` (line 288) catches `Sys_error` but lets other exceptions (e.g., from `int_of_string` in `build_column`) propagate as raw OCaml exceptions rather than structured `VError`.

---

### Finding: `raise exn` re-raise in `write_csv` (Original lines: 419-421)

**Actual lines**: 419-421
**Status**: CONFIRMED

**Evidence**:
```
419:       with exn ->
420:         close_out_noerr ch;
421:         raise exn
```
**Verdict**: Exact match. Same pattern — correct cleanup, but exceptions (e.g., from `value_to_csv_field`) escape as raw OCaml exceptions rather than structured `Error` results. The outer `try/with` at line 425 only catches `Sys_error`.

---

### Finding: `csv_quote_string` uses `sep.[0]` without empty-string guard (Original line: 365)

**Actual line**: 365
**Status**: CONFIRMED (guard exists but edge case noted)

**Evidence**:
```
365:   let has_sep = String.length sep > 0 && String.contains s sep.[0] in
```
**Verdict**: The guard `String.length sep > 0 &&` correctly prevents `sep.[0]` from being called on an empty string (short-circuit evaluation). The review acknowledges this guard but notes the edge case: if `sep` is empty, `has_sep` evaluates to `false`, meaning every string is treated as unquoted. Since `write_csv` defaults to `sep=","`, this is not a practical concern. The finding is technically correct but has negligible real-world impact.
