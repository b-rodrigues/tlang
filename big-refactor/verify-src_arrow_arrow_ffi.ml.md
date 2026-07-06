# Verification Report: src/arrow/arrow_ffi.ml

## File: src/arrow/arrow_ffi.ml

### Finding: Polymorphic type in `arrow_table_new` FFI binding (Original line: 145)

**Actual line**: 145
**Status**: CONFIRMED

**Evidence**:
```
145: external arrow_table_new : (string * int * string option * 'a array) list -> nativeint option
```
**Verdict**: Exact match. The polymorphic `'a array` in the fourth tuple element is used to smuggle heterogeneous OCaml value types (int option array, float option array, nested tuples, etc.) through the FFI. Callers in `arrow_table.ml` (line 694) cast via `Obj.obj`:
```
694: (name, tag, timezone, (Obj.obj raw_data : Obj.t array))
```
This is inherently unsafe — if the C stub expects a different layout than what OCaml provides, memory corruption can result. The review correctly identifies this as an informational finding (not a critical bug, since the codebase works correctly with the current C stubs, but the design is fragile).
