# Verification Report: src/arrow/arrow_bridge.ml

## File: src/arrow/arrow_bridge.ml

### Finding: `raise (Invalid_argument ...)` in `values_to_column` (Original line: 145)

**Actual line**: 145
**Status**: CONFIRMED

**Evidence**:
```
144:     if !has_int || !has_float || !has_bool || !has_string || !has_date || !has_datetime || !has_factor || !factor_inconsistent then
145:       raise (Invalid_argument "values_to_column: mixed DataFrame and non-DataFrame values cannot be stored in a single column")
```
**Verdict**: Exact match. Violates AGENTS.md rule #3 ("No raw OCaml exceptions in user-facing paths"). Reachable via user-provided data (e.g., constructing a mixed-type column in a pipeline step).

---

### Finding: `raise (Invalid_argument ...)` in `table_from_value_columns` (Original line: 268)

**Actual line**: 268
**Status**: CONFIRMED

**Evidence**:
```
267:     if Array.length values <> nrows then
268:       raise (Invalid_argument (Printf.sprintf "table_from_value_columns: column '%s' has length %d but expected %d" name (Array.length values) nrows))
```
**Verdict**: Exact match. Same violation — user-provided column lists with mismatched lengths will crash the program with a raw OCaml exception.

---

### Finding: `values_to_column` exceeds 80-line threshold (Original lines: 83-207)

**Actual lines**: 83-207 (125 lines)
**Status**: CONFIRMED

**Evidence**: The function spans from line 83 (function signature) to line 207 (closing). Contains type inference logic, NA prioritization, fallback chains, and factor inconsistency handling in one monolithic function.

**Verdict**: Exceeds 80-line guideline by ~45 lines.

---

### Finding: Dead type alias `row_count` (Original line: 7)

**Actual line**: 7
**Status**: CONFIRMED

**Evidence**:
```
7: type row_count = int
```
**Verdict**: Defined but never referenced anywhere in any function signature across the arrow module tree. Confirmed unused via grep of the codebase (no imports or references to `row_count` in any function signature).
