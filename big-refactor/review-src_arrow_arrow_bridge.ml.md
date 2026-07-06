# Review: src/arrow/arrow_bridge.ml

**Lines**: 317
**Severity summary**: 2 critical, 2 warnings, 0 info

---

## CRITICAL: Raw OCaml exception in user-facing code path (`values_to_column`)

- **Line 145**: `raise (Invalid_argument "values_to_column: mixed DataFrame and non-DataFrame values cannot be stored in a single column")`

  Violates AGENTS.md rule #3 ("No raw OCaml exceptions in user-facing paths. Return VError {...}"). This is reachable via user-provided data — e.g., constructing a mixed-type column in a pipeline step.

  **Fix**: Return `VError` using `Error.type_error` or `make_error RuntimeError` instead of raising.

## CRITICAL: Raw OCaml exception in user-facing code path (`table_from_value_columns`)

- **Line 268**: `raise (Invalid_argument (Printf.sprintf "table_from_value_columns: column '%s' has length %d but expected %d" name (Array.length values) nrows))`

  Same violation as above. User-provided column lists with mismatched lengths will crash the program.

  **Fix**: Return `VError` instead of raising.

## WARNING: `values_to_column` exceeds 80-line threshold

- **Lines 83–207**: 124 lines. Infers column type, handles NA prioritization, fallback chains, factor inconsistencies, and mixed types — all in one monolithic function.

  **Fix**: Extract as helpers: `infer_column_type` (returns a type tag or error signal), `build_na_column`, `build_string_column_with_fallback`.

## WARNING: Dead type alias `row_count`

- **Line 7**: `type row_count = int` is defined but never used anywhere in the arrow module tree. No function signature references it. It is dead code.

  **Fix**: Remove the unused type alias.
