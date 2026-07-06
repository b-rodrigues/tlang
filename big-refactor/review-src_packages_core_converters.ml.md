# Review: src/packages/core/converters.ml

**Lines**: 198
**Severity summary**: 0 critical, 0 warning, 0 info

---

No issues found. The file is clean and well-structured:

- `lift_unary_converter` properly handles vectors, lists, and scalars with error accumulation.
- All converter functions (`to_integer`, `to_float`, `to_symbol`, `to_bool`, `to_string`) handle NA values correctly (return `VNA NAGeneric` or `VNA NAString`).
- `List.nth_opt` is used at line 187 for safe list access to factor levels.
- Parse errors for numeric strings use `Failure _` catch and return `None`, then produce `VNA NAGeneric`.
- No partial pattern matches, no `Option.get`, no `List.hd`, no unguarded `List.nth`.
