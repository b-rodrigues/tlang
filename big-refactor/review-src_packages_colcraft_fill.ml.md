# Review: src/packages/colcraft/fill.ml

**Lines**: 274
**Severity summary**: 0 critical, 2 warnings, 0 info

---

## WARNING: Duplicate condition (dead code)

- **Line 238**: The condition `(direction = "updown" && Array.exists Option.is_none b)` appears **twice** in the same `if` expression:
  ```
  if direction = "up" || direction = "updown" || (direction = "downup" && Array.exists Option.is_none b) || (direction = "updown" && Array.exists Option.is_none b)
  ```
  The second occurrence is completely redundant since `direction = "up" || direction = "updown"` already covers `"updown"`. All other column-type branches (`IntColumn`, `FloatColumn`, `StringColumn`, `BoolColumn`, `DateColumn`, `DatetimeColumn`) have the same duplicate-free form — only `DictionaryColumn` has this duplicate.

  **Fix**: Remove the second `(direction = "updown" && Array.exists Option.is_none b)` — it is dead code.

---

## WARNING: Function too long / excessive repetition

- **Lines 57–261**: The `fill_col` inner function is ~204 lines with 8 near-identical column-type branches (IntColumn, FloatColumn, StringColumn, BoolColumn, DateColumn, DatetimeColumn, DictionaryColumn, NAColumn/ListColumn). Each branch duplicates ~30 lines of loop logic for up/down/downup/updown filling directions.

  **Fix**: Extract a higher-order helper `fill_array : ('a option array -> 'a option array) -> column -> column` that operates on the underlying array regardless of column type, using a common loop pattern. The string column's special `is_missing` logic (lines 116–119) can be passed as a predicate parameter.
