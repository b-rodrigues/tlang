# Implementation Specification: Arrow Regression Testing Enhancement

## Objective
To strengthen the Arrow-native validation suite by adding targeted tests for memory management, structural integrity, and edge cases that have previously caused `Invalid_argument` errors or segmentation faults.

## 1. Memory Stress & Refcounting Validation
These tests aim to ensure that Arrow objects are not prematurely freed or leaked.

### 1.1 "The Pressure Cooker" (Native Loop Stress)
**Description**: Run a high-frequency loop that creates, materializes, and discards small Arrow tables.
**Goal**: Trigger GLib/Arrow memory management frequently to catch dangling pointers in buffers (like offsets or NA bitmaps).
**Implementation**:
- Loop 10,000 times.
- Each iteration:
    1. Create a `ListColumn` with 2 rows.
    2. Materialize to Native Arrow.
    3. Perform a simple operation (e.g., `nrow`).
    4. Force OCaml GC (`Gc.full_major ()`) to ensure the OCaml wrapper is collected.
    5. Verify no `GLib-GObject-CRITICAL` messages occur.

### 1.2 Schema/Field Lifecycle Test
**Description**: Repeatedly query schemas and field names from the same native table.
**Goal**: Detect "transfer none" vs "transfer full" errors in `caml_arrow_table_get_schema` and `caml_arrow_read_struct_fields`.
**Implementation**:
- Query `get_schema` 100 times in a row for a complex table (nested fields).
- Check that the returned string names are valid each time.
- Verify no double-free or leak occurs.

---

## 2. Structural Integrity (Nested Columns)
These tests target the most complex data paths in the FFI.

### 2.1 Deeply Nested ListColumns
**Description**: Test "List of List of Structs".
**Goal**: Ensure the recursive construction in `arrow_stubs.c` handles depth correctly without corrupting offset buffers.
**Implementation**:
- Create a Table where one column is a `ListColumn` containing sub-tables.
- Those sub-tables should themselves contain `ListColumn`s.
- Materialize and read back the deepest elements.
- Compare with original OCaml values.

### 2.2 ListColumn with Dictionary (Factor) Fields
**Description**: Test a `ListColumn` where the inner DataFrame has Factor columns.
**Goal**: Catch the interaction between List offset management and Dictionary reference management.
**Implementation**:
- Construct `[ [id: 1, type: "A"], [id: 2, type: "B"] ]` as a ListColumn where `type` is a factor.
- Materialize and verify the Dictionary levels are preserved in the nested read-back.

---

## 3. Buffer Management & Null Bitmaps
Specific tests for the raw memory buffers.

### 3.1 Sparse ListColumn (Heavy Nulls)
**Description**: A large `ListColumn` where 90% of entries are `None`.
**Goal**: Verify that the NA bitmap construction correctly offsets bits and doesn't read out of bounds.
**Implementation**:
- Create a 100-row `ListColumn` with data only at index 0 and 99.
- Materialize and read back index 50 (should be `None`).

### 3.2 Multi-Chunk Columns
**Description**: Create a column with multiple chunks and force recombination.
**Goal**: Validate `garrow_chunked_array_combine` and subsequent data extraction.
**Implementation**:
- Manually construct a `ChunkedArray` in C (exposed via a test helper) with 3 small chunks.
- Call `caml_arrow_table_get_column_data_by_name`.
- Verify the single contiguous array contains all data in order.

---

## 4. Integration with T Language (Regression Guards)
High-level guards to catch regressions in the main `eval.ml` Path.

### 4.1 "The Slicer" (Mutation + native)
**Description**: Complex T script that forces native materialization then slices the result.
**Goal**: Catch the `Array.sub` regression in a real-world script.
**Implementation**:
```t
df = dataframe([[grp: "A", val: 1], [grp: "B", val: 2]]);
nested = nest(df, data = -grp); 
# nested now has a ListColumn 'data'
mat = materialize_native(nested);
slice(mat, 1:1); # Trigger Arrow_table.slice_column
```

---

## 5. Automated Checkers
- **AddressSanitizer (ASAN)**: Add instructions to run the runner with ASAN enabled to catch the buffer overflows seen during debugging.
- **Valgrind/LeakSanitizer**: Check for the common "DataType" leaks found in Phase 1.

## Summary Checklist for New Tests:
- [ ] Nested ListColumn round-trip (2+ levels).
- [ ] DictionaryColumn in Nested ListColumn.
- [ ] High-frequency Materialize/GC loop.
- [ ] All-Null and Zero-Null ListColumns.
- [ ] Multi-chunk dictionary columns.
