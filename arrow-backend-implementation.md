# Updated Implementation Plan — Arrow-Backed DataFrame for T

**Status**: Post-Alpha 0.1  
**Goal**: Upgrade T's DataFrame from simple OCaml arrays to Apache Arrow-backed, production-quality tabular data structures comparable to R's data.frame

---

## Current State (Alpha 0.1 — Complete ✓)

The alpha release includes:

✓ **Simple DataFrame Implementation**
- Type: `dataframe = { columns: (string * value array) list; nrows: int; group_keys: string list }`
- CSV reading with type inference (Int, Float, Bool, String, NA)
- Column access via dot notation (`df.age`)
- Basic colcraft verbs (select, filter, mutate, arrange, group_by, summarize)

✓ **Tree-Walking Interpreter**
- All operations use pure OCaml arrays
- No Arrow integration
- No Owl integration
- Functional and correct, but not performant for large datasets

**Limitations**:
- No Apache Arrow backing
- No zero-copy operations
- No Arrow Compute kernels
- Limited to single-threaded, in-memory operations
- No interoperability with other data tools

---

## Implementation Roadmap — Arrow Integration

This plan transforms T's DataFrame from a simple prototype into a production-grade, Arrow-backed implementation.

---

## Phase 1 — Arrow C GLib Integration (Foundation)

**Objective**: Establish FFI bridge to Apache Arrow C GLib library

**Status**: NOT STARTED

### Deliverables

1. **OCaml Bindings to Arrow C GLib**
   - C stubs in `src/ffi/arrow_stubs.c`
   - OCaml interface in `src/arrow/arrow_ffi.ml`
   - Memory-safe wrappers with GC finalizers

2. **Core Arrow Types**
   ```ocaml
   (* src/arrow/arrow_types.ml *)
   type arrow_table  (* Opaque pointer to GArrowTable *)
   type arrow_schema (* Schema with column names and types *)
   type arrow_array  (* Columnar array *)
   type arrow_chunked_array
   ```

3. **Memory Management**
   ```ocaml
   (* src/arrow/arrow_table.ml *)
   type t = {
     ptr : nativeint;           (* C++ object pointer *)
     schema : arrow_schema;     (* Cached schema *)
     nrows : int;               (* Cached row count *)
   }
   
   (* Register GC finalizer *)
   let create ptr schema nrows =
     let table = { ptr; schema; nrows } in
     Gc.finalise arrow_table_free table;
     table
   
   external arrow_table_free : t -> unit = "caml_arrow_table_free"
   ```

### Tasks

1. **Install Arrow C GLib**
   - Update `flake.nix` to include `arrow-glib` package
   - Verify library availability via `pkg-config`

2. **Implement C Stubs**
   ```c
   /* src/ffi/arrow_stubs.c */
   #include <arrow-glib/arrow-glib.h>
   #include <caml/mlvalues.h>
   #include <caml/memory.h>
   #include <caml/alloc.h>
   
   /* Free Arrow table when OCaml GC collects it */
   CAMLprim value caml_arrow_table_free(value v_table) {
     CAMLparam1(v_table);
     GArrowTable *table = (GArrowTable *)Nativeint_val(Field(v_table, 0));
     if (table != NULL) {
       g_object_unref(table);
     }
     CAMLreturn(Val_unit);
   }
   
   /* Get number of rows */
   CAMLprim value caml_arrow_table_num_rows(value v_table) {
     CAMLparam1(v_table);
     GArrowTable *table = (GArrowTable *)Nativeint_val(Field(v_table, 0));
     gint64 nrows = garrow_table_get_n_rows(table);
     CAMLreturn(Val_int(nrows));
   }
   
   /* Get number of columns */
   CAMLprim value caml_arrow_table_num_columns(value v_table) {
     CAMLparam1(v_table);
     GArrowTable *table = (GArrowTable *)Nativeint_val(Field(v_table, 0));
     guint ncols = garrow_table_get_n_columns(table);
     CAMLreturn(Val_int(ncols));
   }
   ```

3. **OCaml Wrapper Interface**
   ```ocaml
   (* src/arrow/arrow_ffi.ml *)
   external arrow_table_free : nativeint -> unit = "caml_arrow_table_free"
   external arrow_table_num_rows : nativeint -> int = "caml_arrow_table_num_rows"
   external arrow_table_num_columns : nativeint -> int = "caml_arrow_table_num_columns"
   external arrow_table_get_column_by_name : nativeint -> string -> nativeint option = "caml_arrow_table_get_column_by_name"
   ```

4. **Build Configuration**
   - Update `src/dune` to link against Arrow C GLib
   - Add C stubs compilation flags

### Acceptance Criteria

- ✓ Can create and free Arrow tables from OCaml
- ✓ No memory leaks (verified with valgrind)
- ✓ GC finalizers work correctly
- ✓ Can query table dimensions (nrow, ncol)

---

## Phase 2 — Arrow-Backed read_csv()

**Objective**: Replace simple CSV parser with Arrow CSV reader

### Deliverables

1. **Arrow CSV Reader**
   ```ocaml
   (* src/arrow/arrow_io.ml *)
   val read_csv : string -> (Arrow_table.t, error_info) result
   ```

2. **Schema Extraction**
   ```ocaml
   (* src/arrow/arrow_table.ml *)
   val get_schema : t -> arrow_schema
   val column_names : t -> string list
   val column_type : t -> string -> arrow_type option
   ```

3. **Updated DataFrame Type**
   ```ocaml
   (* src/ast.ml *)
   type dataframe = {
     arrow_table : Arrow_table.t;  (* Arrow-backed! *)
     group_keys : string list;
   }
   ```

### Tasks

1. **Implement Arrow CSV C Stubs**
   ```c
   /* Read CSV file using Arrow CSV reader */
   CAMLprim value caml_arrow_read_csv(value v_path) {
     CAMLparam1(v_path);
     CAMLlocal1(v_result);
     
     const char *path = String_val(v_path);
     GArrowCSVReader *reader = garrow_csv_reader_new(path, NULL, &error);
     if (!reader) {
       /* Return error */
     }
     
     GArrowTable *table = garrow_csv_reader_read(reader, &error);
     if (!table) {
       /* Return error */
     }
     
     /* Wrap in OCaml value */
     v_result = caml_alloc(1, 0);  /* Some(...) */
     Store_field(v_result, 0, caml_copy_nativeint((intnat)table));
     
     g_object_unref(reader);
     CAMLreturn(v_result);
   }
   ```

2. **Update read_csv() in T**
   ```ocaml
   (* src/packages/dataframe/t_read_csv.ml *)
   let register env =
     Env.add "read_csv"
       (make_builtin 1 (fun args _env ->
         match args with
         | [VString path] ->
             (match Arrow_io.read_csv path with
              | Ok arrow_table ->
                  VDataFrame { arrow_table; group_keys = [] }
              | Error err -> VError err)
         | _ -> make_error TypeError "read_csv() expects a String path"
       ))
       env
   ```

3. **Update nrow(), ncol(), colnames()**
   ```ocaml
   (* src/packages/dataframe/nrow.ml *)
   let register env =
     Env.add "nrow"
       (make_builtin 1 (fun args _env ->
         match args with
         | [VDataFrame { arrow_table; _ }] ->
             VInt (Arrow_table.num_rows arrow_table)
         | _ -> make_error TypeError "nrow() expects a DataFrame"
       ))
       env
   ```

### Acceptance Criteria

- ✓ `read_csv()` returns Arrow-backed DataFrame
- ✓ Type inference works (Int, Float, Bool, String, NA)
- ✓ Schema is correctly extracted
- ✓ Existing tests pass with Arrow backend

---

## Phase 3 — Arrow Compute Kernels for Colcraft Verbs

**Objective**: Implement select, filter, mutate using Arrow Compute

### Deliverables

1. **Arrow Compute Wrappers**
   ```ocaml
   (* src/arrow/arrow_compute.ml *)
   val project : Arrow_table.t -> string list -> Arrow_table.t
   val filter : Arrow_table.t -> (row_dict -> bool) -> Arrow_table.t
   val add_column : Arrow_table.t -> string -> Arrow_array.t -> Arrow_table.t
   ```

2. **Updated Colcraft Verbs**
   - `select()` uses Arrow projection (zero-copy)
   - `filter()` uses Arrow Compute filter kernel
   - `mutate()` uses Arrow Compute scalar operations
   - `arrange()` uses Arrow Compute sort kernel

### Tasks

1. **Implement select() with Arrow Project**
   ```c
   /* src/ffi/arrow_stubs.c */
   CAMLprim value caml_arrow_table_project(value v_table, value v_column_names) {
     CAMLparam2(v_table, v_column_names);
     CAMLlocal1(v_result);
     
     GArrowTable *table = /* extract from v_table */;
     
     /* Convert OCaml string list to GList */
     GList *column_names = NULL;
     while (v_column_names != Val_emptylist) {
       value head = Field(v_column_names, 0);
       column_names = g_list_prepend(column_names, String_val(head));
       v_column_names = Field(v_column_names, 1);
     }
     column_names = g_list_reverse(column_names);
     
     /* Project columns (zero-copy) */
     GArrowTable *result = garrow_table_select_columns(table, column_names, &error);
     
     /* Wrap result */
     v_result = /* wrap as nativeint */;
     CAMLreturn(v_result);
   }
   ```

2. **Implement filter() with Arrow Compute**
   ```c
   /* For now: row-by-row evaluation with Arrow access */
   /* Future: compile predicates to Arrow Compute expressions */
   CAMLprim value caml_arrow_table_filter_rows(value v_table, value v_predicate, value v_env) {
     /* This will call back into OCaml evaluator for each row */
     /* Extract row as Dict, call predicate, collect keep indices */
     /* Use Arrow Take kernel to select rows */
   }
   ```

3. **Update Colcraft Verbs**
   ```ocaml
   (* src/packages/colcraft/t_select.ml *)
   let register env =
     Env.add "select"
       (make_builtin ~variadic:true 1 (fun args _env ->
         match args with
         | VDataFrame { arrow_table; group_keys } :: col_args ->
             let col_names = (* extract string list *) in
             let new_table = Arrow_compute.project arrow_table col_names in
             VDataFrame { arrow_table = new_table; group_keys }
         | _ -> make_error TypeError "select() expects DataFrame"
       ))
       env
   ```

### Acceptance Criteria

- ✓ `select()` performs zero-copy projection
- ✓ `filter()` uses Arrow kernels
- ✓ `mutate()` creates new Arrow columns
- ✓ All existing colcraft tests pass
- ✓ Performance is measurably better for large datasets (>100k rows)

---

## Phase 4 — Column Access and Vector Operations

**Objective**: Implement efficient column extraction and vector operations

### Deliverables

1. **Zero-Copy Column Views**
   ```ocaml
   (* src/arrow/arrow_column.ml *)
   type column_view = {
     backing : Arrow_table.t;     (* Keep table alive *)
     column_name : string;
     array : Arrow_array.t;
   }
   
   val get_column : Arrow_table.t -> string -> column_view
   ```

2. **Vector to Value Array Conversion**
   ```ocaml
   (* Convert Arrow column to T value array for compatibility *)
   val column_to_values : column_view -> value array
   ```

3. **Updated Dot Access**
   ```ocaml
   (* src/eval.ml *)
   | VDataFrame { arrow_table; _ } ->
       let col_view = Arrow_column.get_column arrow_table field in
       let values = Arrow_column.column_to_values col_view in
       VVector values
   ```

### Acceptance Criteria

- ✓ `df.column_name` works with Arrow backend
- ✓ Column data is converted lazily
- ✓ Memory is managed correctly (no leaks)
- ✓ NA values are preserved

---

## Phase 5 — group_by() and summarize() with Arrow

**Objective**: Implement grouped operations using Arrow hash-based grouping

### Deliverables

1. **Arrow Group-By**
   ```ocaml
   (* src/arrow/arrow_compute.ml *)
   type group_indices = {
     keys : Arrow_table.t;        (* Unique group keys *)
     indices : int array array;   (* Row indices per group *)
   }
   
   val group_by : Arrow_table.t -> string list -> group_indices
   ```

2. **Arrow Aggregations**
   ```ocaml
   val aggregate_column : 
     Arrow_array.t -> 
     (value array -> value) ->  (* T aggregation function *)
     group_indices -> 
     value array
   ```

3. **Updated summarize()**
   ```ocaml
   (* Use Arrow for grouping, call T functions for aggregation *)
   let eval_summarize grouped_df agg_exprs =
     match grouped_df.group_keys with
     | [] -> (* ungrouped case *)
     | keys ->
         let group_indices = Arrow_compute.group_by grouped_df.arrow_table keys in
         (* For each group, extract subset and apply aggregation *)
   ```

### Acceptance Criteria

- ✓ `group_by()` uses Arrow hash grouping
- ✓ `summarize()` leverages Arrow aggregations where possible
- ✓ Falls back to T functions for custom aggregations
- ✓ Performance is competitive with R's dplyr

---

## Phase 6 — Owl Integration for Numeric Operations

**Objective**: Bridge Arrow numeric columns to Owl for statistical operations

**Status**: Post-Arrow (can be done in parallel with Arrow work)

### Deliverables

1. **Zero-Copy Arrow → Owl Bridge**
   ```ocaml
   (* src/arrow/arrow_owl_bridge.ml *)
   type owl_view = {
     backing : Arrow_table.t;     (* Keep table alive *)
     column : string;
     arr : Owl.Arr.t;             (* Bigarray view *)
   }
   
   val numeric_column_view : Arrow_table.t -> string -> owl_view option
   ```

2. **Updated lm() and cor()**
   ```ocaml
   (* src/packages/stats/lm.ml *)
   let eval_lm df y_col x_col =
     match Arrow_owl_bridge.numeric_column_view df.arrow_table y_col with
     | Some y_view ->
         (* Use Owl for regression *)
         Owl_wrappers.linear_regression y_view.arr x_view.arr
     | None ->
         make_error TypeError "Column is not numeric or contains NAs"
   ```

### Acceptance Criteria

- ✓ Numeric columns can be viewed as Owl arrays (zero-copy when possible)
- ✓ `lm()` uses Owl for regression
- ✓ `cor()` uses Owl for correlation
- ✓ NA values are handled explicitly

---

## Implementation Priorities

### **Priority 1: Arrow Foundation** (Weeks 1-2)
- Phase 1: Arrow C GLib Integration
- Goal: Can create, free, and query Arrow tables from OCaml

### **Priority 2: Arrow CSV Reading** (Week 3)
- Phase 2: Arrow-Backed read_csv()
- Goal: `read_csv()` returns Arrow-backed DataFrames

### **Priority 3: Core Verbs** (Weeks 4-5)
- Phase 3: select(), filter(), mutate() with Arrow Compute
- Goal: Basic data manipulation works with Arrow backend

### **Priority 4: Advanced Operations** (Weeks 6-7)
- Phase 4: Column access and vector operations
- Phase 5: group_by() and summarize()
- Goal: Full colcraft API works with Arrow

### **Priority 5: Statistics** (Week 8+)
- Phase 6: Owl integration for numeric operations
- Goal: Statistical functions leverage Owl performance

---

## Success Criteria

T's DataFrame is considered complete when:

✓ **Functionality**: All existing alpha tests pass with Arrow backend
✓ **Performance**: 10x faster than alpha for datasets >100k rows
✓ **Memory**: Zero-copy operations where possible
✓ **Interoperability**: Can export to Arrow IPC format
✓ **API Compatibility**: No breaking changes to user-facing T code
✓ **Production-Ready**: Memory-safe, no leaks, stable

---

## Testing Strategy

### Unit Tests
- Arrow FFI memory management (valgrind)
- Arrow table creation and destruction
- Schema extraction and type inference

### Integration Tests
- All existing alpha tests must pass
- Performance benchmarks (vs alpha implementation)
- Memory usage tests (large datasets)

### Golden Tests
- Compare outputs with R's data.frame operations
- Verify numerical accuracy (vs Owl, GSL)

---

## Risks and Mitigation

### Risk 1: Arrow C GLib API Complexity
**Mitigation**: Start with minimal subset (table creation, CSV reading, basic operations)

### Risk 2: Memory Management at FFI Boundary
**Mitigation**: Extensive testing with valgrind, clear ownership model, finalizers

### Risk 3: Performance May Not Meet Expectations
**Mitigation**: Benchmark early, identify bottlenecks, optimize iteratively

### Risk 4: Breaking Changes to User Code
**Mitigation**: Maintain API compatibility, internal implementation changes only

---

## Next Steps

1. **Set up Arrow C GLib dependencies** in `flake.nix`
2. **Create `src/ffi/` and `src/arrow/` directories**
3. **Implement Phase 1: Arrow C GLib Integration**
4. **Write comprehensive tests** for memory management
5. **Implement Phase 2: Arrow-backed read_csv()**
6. **Verify existing tests pass** with new backend

**The goal is clear**: Transform T's DataFrame from a prototype into a production-grade, Arrow-backed tabular data structure on par with R's data.frame, while maintaining full API compatibility with the alpha release.
