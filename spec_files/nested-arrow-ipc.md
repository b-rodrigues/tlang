# Specification: Full Nested Data Support in Arrow IPC

## Objective
Enable seamless `nest()` and `unnest()` operations to survive Arrow IPC serialization round-trips. This requires expanding the native materialization layer to support complex nested schemas.

## Current Limitations
- **Type Restriction**: `ListColumn` (from `nest()`) can only be materialized if nested fields are primitive (Int, Float, Bool, String, Date).
- **Factor/Timestamp Gap**: Nested `Factor` (Dictionary) and `Timestamp` columns currently trigger a fallback to native OCaml storage, blocking Arrow IPC writes.
- **Empty Nesting**: `nest()` on an empty group or a group where all columns are NA cannot currently determine a schema, causing materialization to fail.

## Proposed Implementation

### 1. Nested Dictionary Support
Update `flatten_list_column` in `src/arrow/arrow_table.ml` to handle `DictionaryColumn` within nested tables.
- **FFI Requirement**: The `arrow_table_new` FFI needs to support `List<Dictionary<...>>` construction.
- **Mapping**: Map `VFactor` in nested cells to Arrow `Dictionary` type within the `Struct` representing the row.

### 2. Nested Timestamp Support
Ensure `ArrowTimestamp` is treated as a supported primitive tag in `is_primitive_tag_supported`.
- **Timezone Preservation**: Nested timestamps must preserve their timezone metadata across the IPC boundary.

### 3. Schema Inference for Empty/NA Lists
When a `ListColumn` contains only `None` or empty DataFrames:
- **Fallback Schema**: Use the parent table's unnested schema (minus grouping keys) to provide a "hint" to Arrow for the empty list schema.
- **Nullability**: Ensure `List<Struct<...>>` correctly handles 100% null entries without losing type information.

## Success Criteria
- [ ] `df |> group_by(a) |> nest() |> write_arrow("test.arrow")` works regardless of column types.
- [ ] `read_arrow("test.arrow") |> unnest(data)` restores the original DataFrame schema and types (including Factors).
- [ ] Round-trip regression tests added to `tests/arrow/test_arrow_integration.ml`.
