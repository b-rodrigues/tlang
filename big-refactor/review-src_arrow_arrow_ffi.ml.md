# Review: src/arrow/arrow_ffi.ml

**Lines**: 372
**Severity summary**: 0 critical, 0 warning, 1 info

---

## INFO: Polymorphic type in `arrow_table_new` FFI binding

- **Line 145**: `external arrow_table_new : (string * int * string option * 'a array) list -> nativeint option`

  The fourth tuple element uses a polymorphic `'a array` to smuggle heterogeneous OCaml value types (int option array, float option array, nested tuples, etc.) through the FFI. Callers (in `arrow_table.ml` line 694) cast to `(Obj.t array)` via `Obj.obj`. This is inherently unsafe — if the C stub expects a different representation than what OCaml sends, memory corruption can occur.

  **Fix**: Define explicit external bindings per column type rather than using a single polymorphic binding. If that is impractical, document the exact type mapping contract between OCaml and C in a comment above this declaration.

---

No other issues found. This file consists entirely of `external` FFI declarations and a single boolean guard. All externals return `option` types where the C side can fail, and all pointer types use `nativeint` consistently. The memory management externals (`arrow_table_free`, `arrow_unref`, `arrow_grouped_table_free`) are properly paired with GC finalizers in `arrow_table.ml` and `arrow_compute.ml`.
