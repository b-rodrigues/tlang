# Implementation Plan: Native Arrow Support for Factors and List-Columns

This document outlines the architecture and steps required to move Factors (Dictionary types) and List-columns from the pure OCaml fallback path into the native Arrow "fast path."

## 1. Overview

Currently, `Arrow_table.materialize` falls back to pure OCaml storage if it encounters a `DictionaryColumn` or `ListColumn`. This limits the performance of DataFrames that have been "nested" or contain categorized string data. 

To achieve native support, we need to:
1.  Extend the OCaml <-> C FFI bridge to handle complex Arrow types.
2.  Implement native builders for Dictionary and List arrays in `arrow_stubs.c`.
3.  Update the materialization logic to decompose complex OCaml structures into Arrow-compatible buffers.

---

## 2. Phase 1: Native Factor Support (Dictionary)

Factors are the highest priority as they are used extensively in statistical computing.

### **C FFI Changes (`arrow_stubs.c`)**
*   **Tag Expansion**: Define `arrow_dictionary_tag = 4`.
*   **New Type Support**: In `caml_arrow_table_new`, handle the dictionary tag.
    *   Expect the OCaml data to be a tuple or a custom record containing: `(indices: int option array, levels: string list, ordered: bool)`.
    *   **Logic**:
        1.  Build a `GArrowInt32Array` for the indices (mapping OCaml `int option` to Arrow `int32`).
        2.  Build a `GArrowStringArray` for the dictionary (the levels).
        3.  Construct a `GArrowDictionaryDataType` with the correct index type and value type.
        4.  Create the `GArrowDictionaryArray` using the data type, dictionary, and indices.
*   **Reading Support**: Implement `caml_arrow_read_dictionary_column`.
    *   Extract levels using `garrow_dictionary_array_get_dictionary`.
    *   Extract indices using `garrow_dictionary_array_get_indices`.

### **OCaml Logic (`arrow_table.ml` / `arrow_bridge.ml`)**
*   Update `is_arrow_table_new_supported` to return `true` for `DictionaryColumn`.
*   Update `materialize` to package the levels and indices into the FFI-expected format.
*   Update `get_column` to handle the `ArrowDictionary` case by calling the new FFI reader.

---

## 3. Phase 2: Native List-Column Support

List-columns (nested DataFrames) are more complex because they are recursive.

### **Flattening Strategy**
Arrow represents a List array as a single flattened "values" array (containing all rows of all nested tables) and an "offsets" array.

1.  **Decomposition**:
    *   Validate that all nested DataFrames in the column have the same schema.
    *   Flatten the nested tables into one large OCaml table.
    *   Record the start/end offsets (indices) for each row.
2.  **FFI Building**:
    *   **Tag Expansion**: Define `arrow_list_tag = 5`.
    *   The FFI receives `(offsets: int array, values_table: GArrowTable)`.
    *   Construct the `GArrowListArray` using the offsets and the flattened column data.

### **Reading Support**
*   Implement `caml_arrow_read_list_column`.
*   This must return an array of "slices" of the child array, which the OCaml bridge can then wrap into new `Arrow_table.t` records.

---

## 4. Implementation Steps

### **Step 1: Unified FFI Column Spec**
Change the signature of `arrow_table_new` to use a more robust Variant type instead of an untyped triple:

```ocaml
type ffi_column_spec =
  | Int64 of string * int option array
  | String of string * string option array
  | Dictionary of string * int option array * string list * bool
  | List of string * int32 array * ffi_column_spec (* Recursive! *)
```

### **Step 2: C Stub Robustness**
*   Ensure `GArrowDictionaryArray` builders handle NA values in indices correctly.
*   Implement `caml_arrow_read_dictionary_column` with multi-chunk support.

### **Step 3: Bridge Optimization**
*   In `Arrow_bridge.values_to_column`, ensure that the inferred `DictionaryColumn` preserves metadata (levels) even if some rows are empty.

---

## 5. Success Criteria
*   `explain(df).storage_backend` returns `"native_arrow"` for DataFrames containing factors.
*   `mutate(df, $f = factor(...))` does not drop the native handle.
*   Performance of `filter` and `select` on nested/factor data matches native primitive performance.

---

## 6. Implementation Status

### Phase 1: Native Factor Support — ✅ IMPLEMENTED
*   **C FFI** (`arrow_stubs.c`):
    *   Schema extraction detects `GArrowDictionaryDataType` → tag 4 (`ArrowDictionary`).
    *   `caml_arrow_table_new` case 4 builds `GArrowDictionaryArray` from OCaml `(int option array * string list * bool)`.
    *   `caml_arrow_read_dictionary_column` extracts indices, levels, and ordered flag from a native dictionary column. Non-string dictionary values are explicitly rejected (returns empty result). All integer index widths including `UINT64` are supported, with unsupported types treated as null.
*   **OCaml** (`arrow_table.ml`, `arrow_ffi.ml`):
    *   `arrow_type_of_tag 4` → `ArrowDictionary`.
    *   `is_arrow_table_new_supported` returns `true` for `DictionaryColumn`.
    *   `materialize` packs `DictionaryColumn` data as `(indices, levels, ordered)` tuple for FFI.
    *   `get_column` calls `arrow_read_dictionary_column` for native-backed dictionary columns.
*   **Tests**: Dictionary column round-trip (create → materialize → read), bridge VFactor ↔ DictionaryColumn, T-level factor operations.

### Phase 2: Native List-Column Support — ✅ IMPLEMENTED
*   **C FFI** (`arrow_stubs.c`):
    *   Schema extraction detects `GArrowListDataType` → tag 5 (`ArrowList`).
    *   `caml_arrow_read_list_column` returns child array pointer and per-row offset/length slices.
    *   `caml_arrow_read_struct_fields` extracts field names and type tags from a struct array child.
    *   `caml_arrow_read_struct_field` extracts individual field arrays by index from a struct array.
    *   `caml_arrow_unref` provides generic GObject cleanup for child array pointers.
    *   Builder (case 5) in `caml_arrow_table_new` builds `GArrowListArray` from:
        - Flattened struct child arrays (built per-field using same builder logic as cases 0–3)
        - Int32 offsets buffer marking sub-table boundaries
        - Null bitmap for tracking which list entries are null (None)
*   **OCaml** (`arrow_table.ml`, `arrow_ffi.ml`):
    *   `arrow_type_of_tag 5` → `ArrowList ArrowNull`.
    *   `is_arrow_table_new_supported` returns `true` for `ListColumn` when all sub-tables have same schema of primitive-only fields.
    *   `flatten_list_column` decomposes `ListColumn` into (offsets, present flags, flattened sub-column specs) for FFI.
    *   `materialize` packs `ListColumn` data as `(offsets, present, sub_cols)` tuple for FFI case 5.
    *   `read_native_list_column_from_ptr` reconstructs `ListColumn` from native Arrow by composing `arrow_read_list_column`, `arrow_read_struct_fields`, and per-field column readers, then slicing flattened data into sub-tables.
    *   `get_column` calls `read_native_list_column_from_ptr` for native-backed list columns.
*   **Tests**: ListColumn creation, schema type, pure OCaml read-back, materialization to native, native round-trip (including sub-table data verification), null entry handling, empty list column support, T-language nest/unnest round-trip.
