# Updated Implementation Plan — Arrow-Backed DataFrame for T

# Part 1

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


Part 2: what is missing after Part 1

# Arrow Backend: What Remains To Be Done

## 🔴 **Everything is Stubbed Out**

The current implementation is a **pure OCaml fallback**. None of the Arrow C GLib integration exists. Here's what needs to happen:

---

## **Phase 1: Arrow C GLib Integration** (CRITICAL - 2-3 weeks)

### Status: ❌ NOT STARTED

### What's Missing:

#### 1. **Build System Configuration**
```bash
# In flake.nix - arrow-glib is listed but not configured
# Need to add:
- pkg-config setup for arrow-glib
- C compilation flags extraction
```

#### 2. **C FFI Stubs** (`src/ffi/arrow_stubs.c`)
Current state: Exists but commented out behind `#ifdef ARROW_GLIB_AVAILABLE`

**Need to implement and activate:**
```c
// Memory management
caml_arrow_table_free()           ❌ Commented out
caml_arrow_table_num_rows()       ❌ Commented out  
caml_arrow_table_num_columns()    ❌ Commented out

// Column access
caml_arrow_table_get_column_by_name()  ❌ Commented out

// CSV reading
caml_arrow_read_csv()              ❌ Commented out

// Operations
caml_arrow_table_project()         ❌ Commented out
caml_arrow_table_filter_mask()     ❌ Commented out
```

#### 3. **OCaml FFI Wrappers** (`src/arrow/arrow_ffi.ml`)
Current state: All `external` declarations commented out

**Need to uncomment and activate:**
```ocaml
external arrow_table_free : nativeint -> unit              ❌
external arrow_table_num_rows : nativeint -> int           ❌
external arrow_read_csv : string -> nativeint option       ❌
external arrow_table_project : ...                         ❌
external arrow_table_filter : ...                          ❌
```

#### 4. **Dune Build Integration** (`src/dune`)
Current state: No foreign_stubs configuration

**Need to add:**
```lisp
(foreign_stubs
  (language c)
  (names arrow_stubs)
  (flags (:include arrow_cflags.sexp)))
```

#### 5. **GC Finalizers for Memory Safety**
Current state: NOT implemented

**Need to add:**
```ocaml
(* arrow_table.ml *)
let create ptr schema nrows =
  let table = { ptr; schema; nrows } in
  Gc.finalise arrow_table_free table;  ❌ NOT DONE
  table
```

---

## **Phase 2: Arrow-Backed CSV Reading** (1 week)

### Status: ❌ NOT STARTED

Current `arrow_io.ml` uses pure OCaml parsing. Need to replace with:

#### What's Missing:

1. **Arrow CSV Reader C Stub**
```c
// src/ffi/arrow_stubs.c
CAMLprim value caml_arrow_read_csv(value v_path) {
  // Use GArrowCSVReader
  // Return GArrowTable pointer
}
```
❌ Exists but commented out

2. **Schema Extraction from Arrow**
```ocaml
(* arrow_table.ml *)
val get_schema : t -> arrow_schema
val column_type : t -> string -> arrow_type option
```
✅ Signatures exist, but not using real Arrow

3. **Update T's read_csv()**
```ocaml
(* src/packages/dataframe/t_read_csv.ml *)
(* Need to call Arrow_io.read_csv instead of parse_csv_string *)
```
⚠️ Needs refactor to use Arrow

---

## **Phase 3: Arrow Compute Kernels** (2-3 weeks)

### Status: ❌ NOT STARTED

Current `arrow_compute.ml` just delegates to pure OCaml. Need to implement:

#### 1. **C Stubs for Arrow Compute**
```c
// Project (zero-copy column selection)
caml_arrow_table_project()         ❌ Commented out

// Filter with boolean mask
caml_arrow_table_filter_mask()     ❌ Commented out

// Sort
caml_arrow_table_sort()            ❌ NOT IMPLEMENTED

// Scalar operations (add, multiply, etc.)
caml_arrow_compute_add()           ❌ NOT IMPLEMENTED
caml_arrow_compute_multiply()      ❌ NOT IMPLEMENTED
```

#### 2. **Update Colcraft Verbs**
All verbs currently use pure OCaml arrays. Need to update:

```ocaml
(* t_select.ml - use Arrow project kernel *)
let new_table = Arrow_compute.project df.arrow_table names
// Currently delegates to arrow_table.ml pure OCaml ❌

(* t_filter.ml - use Arrow filter kernel *)  
let new_table = Arrow_compute.filter df.arrow_table keep
// Currently uses manual array iteration ❌

(* mutate.ml - use Arrow scalar kernels *)
// Currently evaluates row-by-row ❌

(* arrange.ml - use Arrow sort kernel *)
// Currently uses OCaml Array.sort ❌
```

---

## **Phase 4: Zero-Copy Column Access** (1 week)

### Status: ⚠️ PARTIALLY DONE

`arrow_column.ml` exists but doesn't do zero-copy viewing.

#### What's Missing:

1. **Zero-Copy View Type**
```ocaml
type column_view = {
  backing : Arrow_table.t;     (* Keep table alive *)
  column_name : string;
  array : Arrow_array.t;       (* Zero-copy view *)
}
```
✅ Structure exists

2. **Actual Zero-Copy Implementation**
```ocaml
(* Need to create Bigarray view into Arrow buffer *)
let get_column_buffer table col_name =
  // Get pointer to Arrow buffer (C FFI)  ❌ NOT IMPLEMENTED
  // Create bigarray view (no copy)       ❌ NOT IMPLEMENTED
```

---

## **Phase 5: group_by() and summarize() with Arrow** (2 weeks)

### Status: ❌ NOT STARTED

Current implementation does manual grouping in OCaml.

#### What's Missing:

1. **Arrow Group-By C Stub**
```c
// Use garrow_table_group_by or build hash-based grouping
caml_arrow_table_group_by()        ❌ NOT IMPLEMENTED
```

2. **Arrow Aggregation Kernels**
```c
caml_arrow_compute_group_sum()     ❌ NOT IMPLEMENTED
caml_arrow_compute_group_mean()    ❌ NOT IMPLEMENTED
caml_arrow_compute_group_count()   ❌ NOT IMPLEMENTED
```

3. **Update summarize.ml**
```ocaml
(* Use Arrow's hash grouping instead of Hashtbl *)
let group_indices = Arrow_compute.group_by df.arrow_table keys
// Currently uses pure OCaml Hashtbl ❌
```

---

## **Phase 6: Owl Integration** (Optional - can defer to Beta)

### Status: ❌ NOT STARTED

This is for numeric operations (lm, cor, etc.)

#### What's Missing:

1. **Zero-Copy Arrow → Owl Bridge**
```ocaml
(* arrow_owl_bridge.ml - NEW FILE NEEDED *)
val numeric_column_view : Arrow_table.t -> string -> owl_view option
```

2. **Update Stats Functions**
```ocaml
(* lm.ml, cor.ml - use Owl instead of manual computation *)
```

---

## **Priority Roadmap**

### 🔥 **Week 1-2: Build & FFI Foundation**
1. Configure flake.nix for arrow-glib
2. Create arrow_cflags.sexp (pkg-config extraction)
3. Uncomment and compile arrow_stubs.c
4. Uncomment arrow_ffi.ml externals
5. Add foreign_stubs to src/dune
6. **Verify:** Can create and free Arrow tables from OCaml

### 🔥 **Week 3: CSV Reading**
1. Implement Arrow CSV reader C stub
2. Update arrow_io.ml to call FFI
3. Test type inference with Arrow
4. **Verify:** read_csv() returns real Arrow tables

### 🔥 **Week 4-5: Core Compute Kernels**
1. Implement project (select) C stub
2. Implement filter C stub
3. Update t_select.ml and t_filter.ml
4. **Verify:** Zero-copy operations working

### 🔥 **Week 6-7: Complete Colcraft**
1. Implement mutate with Arrow scalars
2. Implement arrange with Arrow sort
3. Update remaining colcraft verbs
4. **Verify:** All colcraft tests pass

### 🔥 **Week 8+: Group-By & Advanced**
1. Implement group_by C stub
2. Implement aggregation kernels
3. Update summarize.ml
4. **Verify:** Performance benchmark shows improvement

---

## **Critical Path Items**

These block everything else:

1. ✅ **arrow-glib installed** (listed in flake.nix, but needs verification)
2. ❌ **pkg-config working** (extract CFLAGS, LIBS)
3. ❌ **C stubs compile** (arrow_stubs.c)
4. ❌ **OCaml can call C stubs** (arrow_ffi.ml externals active)
5. ❌ **Memory management safe** (GC finalizers)

---

## **Testing Checklist**

After each phase:
- ✅ Run existing tests (must still pass)
- ✅ Valgrind for memory leaks
- ✅ Benchmark performance vs pure OCaml
- ✅ Golden tests for output equivalence

---

## **Bottom Line**

**Percentage Complete: ~5%**

- Pure OCaml fallback infrastructure: ✅ Done (scaffolding)
- Arrow C GLib FFI: ❌ 0% (all commented out)
- Arrow Compute integration: ❌ 0%
- Zero-copy operations: ❌ 0%
- Performance benchmarks: ❌ 0%

**Estimated Effort:** 8-10 weeks of focused implementation

**Recommendation:** This is your **top priority** before any Beta features. The entire performance story depends on it.

# Part 3: Arrow Backend Implementation: Complete Checklist

## **Phase 1: Arrow C GLib Integration (Weeks 1-3)**

### **Week 1: Build System & C FFI Foundation**

#### Day 1: Environment Setup
- [ ] **Verify arrow-glib is available**
  ```bash
  nix develop
  pkg-config --modversion arrow-glib
  # Should output version number
  ```
- [ ] **Create pkg-config extraction script**
  ```bash
  # Create: scripts/extract_arrow_flags.sh
  #!/bin/bash
  pkg-config --cflags arrow-glib > arrow_cflags.txt
  pkg-config --libs arrow-glib > arrow_libs.txt
  ```
- [ ] **Generate arrow_cflags.sexp**
  ```bash
  # Create: src/arrow_cflags.sexp
  # Run: pkg-config --cflags arrow-glib | sed 's/ /\n/g' | sed 's/^/(/' | sed 's/$/)/' > src/arrow_cflags.sexp
  ```

#### Day 2: Activate C Stubs (Memory Management)
- [ ] **Uncomment arrow_stubs.c and remove `#ifdef`**
  ```c
  // src/ffi/arrow_stubs.c
  // REMOVE: #ifdef ARROW_GLIB_AVAILABLE
  // REMOVE: #endif
  
  // Keep these functions:
  CAMLprim value caml_arrow_table_free(value v_ptr) { ... }
  CAMLprim value caml_arrow_table_num_rows(value v_ptr) { ... }
  CAMLprim value caml_arrow_table_num_columns(value v_ptr) { ... }
  ```

- [ ] **Update src/dune to compile C stubs**
  ```lisp
  (library
   (name t_lang)
   (wrapped false)
   (foreign_stubs
    (language c)
    (names arrow_stubs)
    (flags (:include arrow_cflags.sexp)))
   (c_library_flags (:include arrow_libs.sexp))
   (modules ...)
   (libraries menhirLib)
  )
  ```

- [ ] **Create arrow_libs.sexp**
  ```bash
  # Run: pkg-config --libs arrow-glib | sed 's/ /\n/g' | sed 's/^/(/' | sed 's/$/)/' > src/arrow_libs.sexp
  ```

#### Day 3: Activate OCaml FFI Wrappers
- [ ] **Uncomment externals in arrow_ffi.ml**
  ```ocaml
  (* src/arrow/arrow_ffi.ml *)
  (* UNCOMMENT: *)
  external arrow_table_free : nativeint -> unit = "caml_arrow_table_free"
  external arrow_table_num_rows : nativeint -> int = "caml_arrow_table_num_rows"
  external arrow_table_num_columns : nativeint -> int = "caml_arrow_table_num_columns"
  ```

- [ ] **Set arrow_available flag to true**
  ```ocaml
  let arrow_available = true  (* Changed from false *)
  ```

- [ ] **Test compilation**
  ```bash
  dune clean
  dune build
  # Should compile without errors
  ```

#### Day 4: Implement GC Finalizers
- [ ] **Add finalizer registration in arrow_table.ml**
  ```ocaml
  (* src/arrow/arrow_table.ml *)
  (* Add at top of file: *)
  
  type native_handle = {
    ptr : nativeint;
    mutable freed : bool;
  }
  
  let create_from_native ptr schema nrows =
    let handle = { ptr; freed = false } in
    let table = { schema; columns = []; nrows; native_handle = Some handle } in
    Gc.finalise (fun h ->
      if not h.freed then begin
        Arrow_ffi.arrow_table_free h.ptr;
        h.freed <- true
      end
    ) handle;
    table
  ```

- [ ] **Update t type to include native_handle**
  ```ocaml
  type t = {
    schema : arrow_schema;
    columns : (string * column_data) list;
    nrows : int;
    native_handle : native_handle option;  (* NEW *)
  }
  ```

#### Day 5: First Integration Test
- [ ] **Create minimal test file: tests/arrow_ffi_test.ml**
  ```ocaml
  (* Test GC finalizer *)
  open Arrow_ffi
  
  let test_finalizer () =
    (* This would need a real Arrow table pointer *)
    (* For now, test that externals are callable *)
    assert (arrow_available = true);
    print_endline "✓ Arrow FFI available"
  
  let () = test_finalizer ()
  ```

- [ ] **Add to tests/dune**
  ```lisp
  (test
   (name arrow_ffi_test)
   (modules arrow_ffi_test)
   (libraries t_lang))
  ```

- [ ] **Run test**
  ```bash
  dune test
  # Should pass
  ```

---

### **Week 2: CSV Reading with Arrow**

#### Day 1: Implement Arrow CSV Reader C Stub
- [ ] **Uncomment caml_arrow_read_csv in arrow_stubs.c**
  ```c
  /* src/ffi/arrow_stubs.c */
  CAMLprim value caml_arrow_read_csv(value v_path) {
    CAMLparam1(v_path);
    CAMLlocal1(v_result);
    
    const char *path = String_val(v_path);
    GError *error = NULL;
    
    // Open input file
    GArrowMemoryMappedInputStream *input =
      garrow_memory_mapped_input_stream_new(path, &error);
    
    // Handle error case
    if (input == NULL) {
      if (error) g_error_free(error);
      CAMLreturn(Val_none);
    }
    
    // Create CSV reader with default options
    GArrowCSVReadOptions *options = garrow_csv_read_options_new();
    GArrowCSVReader *reader =
      garrow_csv_reader_new(GARROW_INPUT_STREAM(input), options, &error);
    g_object_unref(options);
    
    if (reader == NULL) {
      g_object_unref(input);
      if (error) g_error_free(error);
      CAMLreturn(Val_none);
    }
    
    // Read table
    GArrowTable *table = garrow_csv_reader_read(reader, &error);
    g_object_unref(reader);
    g_object_unref(input);
    
    if (table == NULL) {
      if (error) g_error_free(error);
      CAMLreturn(Val_none);
    }
    
    // Wrap as Some(nativeint)
    v_result = caml_alloc(1, 0);
    Store_field(v_result, 0, caml_copy_nativeint((intnat)table));
    CAMLreturn(v_result);
  }
  ```

#### Day 2: Uncomment arrow_read_csv External
- [ ] **Uncomment in arrow_ffi.ml**
  ```ocaml
  external arrow_read_csv : string -> nativeint option = "caml_arrow_read_csv"
  ```

- [ ] **Test compilation**
  ```bash
  dune build
  # Should compile
  ```

#### Day 3: Implement Schema Extraction
- [ ] **Add schema extraction C stub**
  ```c
  /* src/ffi/arrow_stubs.c - NEW FUNCTION */
  CAMLprim value caml_arrow_table_get_schema(value v_ptr) {
    CAMLparam1(v_ptr);
    CAMLlocal2(v_result, v_col);
    
    GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
    GArrowSchema *schema = garrow_table_get_schema(table);
    guint ncols = garrow_schema_n_fields(schema);
    
    // Build OCaml list of (name, type) pairs
    v_result = Val_emptylist;
    for (gint i = ncols - 1; i >= 0; i--) {
      GArrowField *field = garrow_schema_get_field(schema, i);
      const gchar *name = garrow_field_get_name(field);
      GArrowDataType *dtype = garrow_field_get_data_type(field);
      
      // Map Arrow type to T arrow_type
      int type_tag;
      if (GARROW_IS_INT64_DATA_TYPE(dtype)) type_tag = 0; // ArrowInt64
      else if (GARROW_IS_DOUBLE_DATA_TYPE(dtype)) type_tag = 1; // ArrowFloat64
      else if (GARROW_IS_BOOLEAN_DATA_TYPE(dtype)) type_tag = 2; // ArrowBoolean
      else if (GARROW_IS_STRING_DATA_TYPE(dtype)) type_tag = 3; // ArrowString
      else type_tag = 4; // ArrowNull
      
      // Create tuple (name, type_tag)
      v_col = caml_alloc(2, 0);
      Store_field(v_col, 0, caml_copy_string(name));
      Store_field(v_col, 1, Val_int(type_tag));
      
      // Cons onto list
      value cons = caml_alloc(2, 0);
      Store_field(cons, 0, v_col);
      Store_field(cons, 1, v_result);
      v_result = cons;
      
      g_object_unref(field);
    }
    
    g_object_unref(schema);
    CAMLreturn(v_result);
  }
  ```

- [ ] **Add external in arrow_ffi.ml**
  ```ocaml
  external arrow_table_get_schema : nativeint -> (string * int) list = "caml_arrow_table_get_schema"
  ```

#### Day 4: Bridge Arrow CSV to T
- [ ] **Create arrow_io.ml native implementation**
  ```ocaml
  (* src/arrow/arrow_io.ml *)
  let read_csv (path : string) : (Arrow_table.t, string) result =
    if not Arrow_ffi.arrow_available then
      Error "Arrow C GLib not available"
    else
      match Arrow_ffi.arrow_read_csv path with
      | None -> Error ("Failed to read CSV: " ^ path)
      | Some ptr ->
        let schema_pairs = Arrow_ffi.arrow_table_get_schema ptr in
        let nrows = Arrow_ffi.arrow_table_num_rows ptr in
        let schema = List.map (fun (name, type_tag) ->
          let typ = match type_tag with
            | 0 -> Arrow_table.ArrowInt64
            | 1 -> Arrow_table.ArrowFloat64
            | 2 -> Arrow_table.ArrowBoolean
            | 3 -> Arrow_table.ArrowString
            | _ -> Arrow_table.ArrowNull
          in
          (name, typ)
        ) schema_pairs in
        Ok (Arrow_table.create_from_native ptr schema nrows)
  ```

#### Day 5: Test CSV Reading
- [ ] **Create test CSV: tests/arrow_test.csv**
  ```csv
  name,age,score
  Alice,30,95.5
  Bob,25,87.3
  Charlie,35,92.1
  ```

- [ ] **Create test: tests/arrow_csv_test.ml**
  ```ocaml
  open Ast
  
  let test_arrow_csv () =
    match Arrow_io.read_csv "tests/arrow_test.csv" with
    | Error msg -> failwith ("CSV read failed: " ^ msg)
    | Ok table ->
      assert (Arrow_table.num_rows table = 3);
      assert (Arrow_table.num_columns table = 3);
      let cols = Arrow_table.column_names table in
      assert (List.mem "name" cols);
      assert (List.mem "age" cols);
      assert (List.mem "score" cols);
      print_endline "✓ Arrow CSV reading works"
  
  let () = test_arrow_csv ()
  ```

- [ ] **Add to tests/dune and run**
  ```bash
  dune test
  ```

---

### **Week 3: Column Access & Data Extraction**

#### Day 1: Implement Column Extraction
- [ ] **Add column extraction C stub**
  ```c
  /* src/ffi/arrow_stubs.c - NEW FUNCTION */
  CAMLprim value caml_arrow_table_get_column_data(value v_ptr, value v_col_name) {
    CAMLparam2(v_ptr, v_col_name);
    CAMLlocal1(v_result);
    
    GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
    const char *col_name = String_val(v_col_name);
    
    GArrowChunkedArray *chunked = garrow_table_get_column_by_name(table, col_name);
    if (chunked == NULL) {
      CAMLreturn(Val_none);
    }
    
    // For now, assume single chunk (simplification)
    GArrowArray *array = garrow_chunked_array_get_chunk(chunked, 0);
    gint64 length = garrow_array_get_length(array);
    
    // Build OCaml array based on type
    // This is simplified - real implementation needs type dispatch
    v_result = caml_alloc(1, 0); // Some(...)
    Store_field(v_result, 0, caml_copy_nativeint((intnat)array));
    
    g_object_unref(chunked);
    // Don't unref array - it's owned by chunked
    
    CAMLreturn(v_result);
  }
  ```

- [ ] **Add external in arrow_ffi.ml**
  ```ocaml
  external arrow_table_get_column_data : nativeint -> string -> nativeint option
    = "caml_arrow_table_get_column_data"
  ```

#### Day 2-3: Implement Type-Specific Column Readers
- [ ] **Add typed column readers in arrow_stubs.c**
  ```c
  /* Read Int64 column */
  CAMLprim value caml_arrow_read_int64_column(value v_array_ptr) {
    CAMLparam1(v_array_ptr);
    CAMLlocal1(v_result);
    
    GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
    gint64 length = garrow_array_get_length(array);
    
    // Allocate OCaml array
    v_result = caml_alloc(length, 0);
    
    GArrowInt64Array *int_array = GARROW_INT64_ARRAY(array);
    for (gint64 i = 0; i < length; i++) {
      if (garrow_array_is_null(array, i)) {
        Store_field(v_result, i, Val_none); // None
      } else {
        gint64 val = garrow_int64_array_get_value(int_array, i);
        value some = caml_alloc(1, 0); // Some(...)
        Store_field(some, 0, Val_long(val));
        Store_field(v_result, i, some);
      }
    }
    
    CAMLreturn(v_result);
  }
  
  /* Similar for Float64, Boolean, String */
  CAMLprim value caml_arrow_read_float64_column(value v_array_ptr) { ... }
  CAMLprim value caml_arrow_read_boolean_column(value v_array_ptr) { ... }
  CAMLprim value caml_arrow_read_string_column(value v_array_ptr) { ... }
  ```

- [ ] **Add externals in arrow_ffi.ml**
  ```ocaml
  external arrow_read_int64_column : nativeint -> int option array = "caml_arrow_read_int64_column"
  external arrow_read_float64_column : nativeint -> float option array = "caml_arrow_read_float64_column"
  external arrow_read_boolean_column : nativeint -> bool option array = "caml_arrow_read_boolean_column"
  external arrow_read_string_column : nativeint -> string option array = "caml_arrow_read_string_column"
  ```

#### Day 4: Update arrow_table.ml to Use Native Columns
- [ ] **Implement get_column with native extraction**
  ```ocaml
  (* src/arrow/arrow_table.ml *)
  let get_column (t : t) (name : string) : column_data option =
    match t.native_handle with
    | None ->
      (* Fallback to pure OCaml *)
      List.assoc_opt name t.columns
    | Some handle ->
      match List.assoc_opt name t.schema with
      | None -> None
      | Some col_type ->
        match Arrow_ffi.arrow_table_get_column_data handle.ptr name with
        | None -> None
        | Some array_ptr ->
          match col_type with
          | ArrowInt64 ->
            let data = Arrow_ffi.arrow_read_int64_column array_ptr in
            Some (IntColumn data)
          | ArrowFloat64 ->
            let data = Arrow_ffi.arrow_read_float64_column array_ptr in
            Some (FloatColumn data)
          | ArrowBoolean ->
            let data = Arrow_ffi.arrow_read_boolean_column array_ptr in
            Some (BoolColumn data)
          | ArrowString ->
            let data = Arrow_ffi.arrow_read_string_column array_ptr in
            Some (StringColumn data)
          | ArrowNull ->
            Some (NullColumn t.nrows)
  ```

#### Day 5: Integration Test
- [ ] **Test end-to-end: CSV → Arrow → Column Access**
  ```ocaml
  (* tests/arrow_integration_test.ml *)
  let test_column_access () =
    match Arrow_io.read_csv "tests/arrow_test.csv" with
    | Error msg -> failwith msg
    | Ok table ->
      match Arrow_table.get_column table "age" with
      | None -> failwith "Column 'age' not found"
      | Some (Arrow_table.IntColumn data) ->
        assert (Array.length data = 3);
        assert (data.(0) = Some 30);
        assert (data.(1) = Some 25);
        assert (data.(2) = Some 35);
        print_endline "✓ Column access works"
      | _ -> failwith "Wrong column type"
  
  let () = test_column_access ()
  ```

---

## **Phase 2: Arrow Compute Kernels (Weeks 4-5)**

### **Week 4: Project & Filter**

#### Day 1: Implement Arrow Project (Select) C Stub
- [ ] **Uncomment caml_arrow_table_project in arrow_stubs.c**
  ```c
  /* Already exists commented out - just uncomment */
  CAMLprim value caml_arrow_table_project(value v_ptr, value v_names) { ... }
  ```

- [ ] **Uncomment external in arrow_ffi.ml**
  ```ocaml
  external arrow_table_project : nativeint -> string list -> nativeint option
    = "caml_arrow_table_project"
  ```

#### Day 2: Implement Arrow Filter C Stub
- [ ] **Uncomment caml_arrow_table_filter_mask in arrow_stubs.c**
  ```c
  /* Already exists commented out */
  CAMLprim value caml_arrow_table_filter_mask(value v_ptr, value v_mask) { ... }
  ```

- [ ] **Uncomment external in arrow_ffi.ml**
  ```ocaml
  external arrow_table_filter_mask : nativeint -> bool array -> nativeint option
    = "caml_arrow_table_filter_mask"
  ```

#### Day 3: Update arrow_compute.ml
- [ ] **Implement native project**
  ```ocaml
  (* src/arrow/arrow_compute.ml *)
  let project (t : Arrow_table.t) (names : string list) : Arrow_table.t =
    match t.native_handle with
    | None ->
      (* Fallback to pure OCaml *)
      Arrow_table.project t names
    | Some handle ->
      match Arrow_ffi.arrow_table_project handle.ptr names with
      | None -> failwith "Arrow project failed"
      | Some new_ptr ->
        let new_schema = List.filter (fun (n, _) -> List.mem n names) t.schema in
        Arrow_table.create_from_native new_ptr new_schema t.nrows
  ```

- [ ] **Implement native filter**
  ```ocaml
  let filter (t : Arrow_table.t) (mask : bool array) : Arrow_table.t =
    match t.native_handle with
    | None ->
      Arrow_table.filter_rows t mask
    | Some handle ->
      match Arrow_ffi.arrow_table_filter_mask handle.ptr mask with
      | None -> failwith "Arrow filter failed"
      | Some new_ptr ->
        let new_nrows = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 mask in
        Arrow_table.create_from_native new_ptr t.schema new_nrows
  ```

#### Day 4: Test Project & Filter
- [ ] **Create test: tests/arrow_compute_test.ml**
  ```ocaml
  let test_project () =
    match Arrow_io.read_csv "tests/arrow_test.csv" with
    | Error msg -> failwith msg
    | Ok table ->
      let projected = Arrow_compute.project table ["name"; "age"] in
      assert (Arrow_table.num_columns projected = 2);
      print_endline "✓ Arrow project works"
  
  let test_filter () =
    match Arrow_io.read_csv "tests/arrow_test.csv" with
    | Error msg -> failwith msg
    | Ok table ->
      let mask = [| true; false; true |] in
      let filtered = Arrow_compute.filter table mask in
      assert (Arrow_table.num_rows filtered = 2);
      print_endline "✓ Arrow filter works"
  
  let () =
    test_project ();
    test_filter ()
  ```

#### Day 5: Update Colcraft select() and filter()
- [ ] **Verify t_select.ml uses arrow_compute.ml**
  ```ocaml
  (* src/packages/colcraft/t_select.ml *)
  (* Should already call Arrow_compute.project *)
  let new_table = Arrow_compute.project df.arrow_table names in
  (* If not using it, update to use it *)
  ```

- [ ] **Verify t_filter.ml uses arrow_compute.ml**
  ```ocaml
  (* src/packages/colcraft/t_filter.ml *)
  let new_table = Arrow_compute.filter df.arrow_table keep in
  (* Update if needed *)
  ```

- [ ] **Run full test suite**
  ```bash
  dune test
  # All existing tests should still pass
  ```

---

### **Week 5: Sort & Scalar Operations**

#### Day 1-2: Implement Arrow Sort
- [ ] **Add sort C stub**
  ```c
  /* src/ffi/arrow_stubs.c - NEW FUNCTION */
  CAMLprim value caml_arrow_table_sort_by_column(value v_ptr, value v_col_name, value v_ascending) {
    CAMLparam3(v_ptr, v_col_name, v_ascending);
    CAMLlocal1(v_result);
    
    GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
    const char *col_name = String_val(v_col_name);
    gboolean ascending = Bool_val(v_ascending);
    
    // Get column index
    GArrowSchema *schema = garrow_table_get_schema(table);
    gint col_idx = garrow_schema_get_field_index(schema, col_name);
    g_object_unref(schema);
    
    if (col_idx < 0) {
      CAMLreturn(Val_none);
    }
    
    // Create sort options
    GArrowSortOptions *options = garrow_sort_options_new();
    GArrowSortKey *sort_key = garrow_sort_key_new(col_idx, ascending ? GARROW_SORT_ORDER_ASCENDING : GARROW_SORT_ORDER_DESCENDING);
    garrow_sort_options_add_sort_key(options, sort_key);
    
    // Sort table
    GError *error = NULL;
    GArrowTable *sorted = garrow_table_sort_indices(table, options, &error);
    
    g_object_unref(options);
    g_object_unref(sort_key);
    
    if (sorted == NULL) {
      if (error) g_error_free(error);
      CAMLreturn(Val_none);
    }
    
    v_result = caml_alloc(1, 0);
    Store_field(v_result, 0, caml_copy_nativeint((intnat)sorted));
    CAMLreturn(v_result);
  }
  ```

- [ ] **Add external in arrow_ffi.ml**
  ```ocaml
  external arrow_table_sort_by_column : nativeint -> string -> bool -> nativeint option
    = "caml_arrow_table_sort_by_column"
  ```

#### Day 3: Update arrow_compute.ml with Sort
- [ ] **Add native sort**
  ```ocaml
  let sort_by_column (t : Arrow_table.t) (col_name : string) (ascending : bool) : Arrow_table.t =
    match t.native_handle with
    | None ->
      (* Fallback to pure OCaml sort_by_indices *)
      failwith "Pure OCaml sort not yet implemented"
    | Some handle ->
      match Arrow_ffi.arrow_table_sort_by_column handle.ptr col_name ascending with
      | None -> failwith "Arrow sort failed"
      | Some new_ptr ->
        Arrow_table.create_from_native new_ptr t.schema t.nrows
  ```

#### Day 4: Implement Scalar Operations (Add/Multiply)
- [ ] **Add scalar operation C stubs**
  ```c
  /* src/ffi/arrow_stubs.c - NEW FUNCTIONS */
  
  /* Add scalar to column */
  CAMLprim value caml_arrow_column_add_scalar(value v_array_ptr, value v_scalar) {
    CAMLparam2(v_array_ptr, v_scalar);
    CAMLlocal1(v_result);
    
    GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
    
    // Use Arrow Compute add kernel
    GError *error = NULL;
    GArrowDatum *datum_array = garrow_datum_new_array(array);
    
    // Create scalar datum based on type
    double scalar_val = Double_val(v_scalar);
    GArrowScalar *scalar = garrow_double_scalar_new(scalar_val);
    GArrowDatum *datum_scalar = garrow_datum_new_scalar(scalar);
    
    // Call compute function
    GArrowAddOptions *options = garrow_add_options_new();
    GArrowDatum *result_datum = garrow_function_call("add", datum_array, datum_scalar, options, &error);
    
    g_object_unref(options);
    g_object_unref(datum_array);
    g_object_unref(datum_scalar);
    g_object_unref(scalar);
    
    if (result_datum == NULL) {
      if (error) g_error_free(error);
      CAMLreturn(Val_none);
    }
    
    GArrowArray *result_array = garrow_datum_get_array(result_datum);
    v_result = caml_alloc(1, 0);
    Store_field(v_result, 0, caml_copy_nativeint((intnat)result_array));
    
    g_object_unref(result_datum);
    CAMLreturn(v_result);
  }
  
  /* Similar for multiply, subtract, divide */
  ```

- [ ] **Add externals in arrow_ffi.ml**
  ```ocaml
  external arrow_column_add_scalar : nativeint -> float -> nativeint option
  external arrow_column_multiply_scalar : nativeint -> float -> nativeint option
  ```

#### Day 5: Update arrange.ml
- [ ] **Use native Arrow sort in arrange.ml**
  ```ocaml
  (* src/packages/colcraft/arrange.ml *)
  let register env =
    Env.add "arrange"
      (make_builtin ~variadic:true 2 (fun args _env ->
        match args with
        | [VDataFrame df; VString col_name] | [VDataFrame df; VString col_name; VString "asc"] ->
          let new_table = Arrow_compute.sort_by_column df.arrow_table col_name true in
          VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
        | [VDataFrame df; VString col_name; VString "desc"] ->
          let new_table = Arrow_compute.sort_by_column df.arrow_table col_name false in
          VDataFrame { arrow_table = new_table; group_keys = df.group_keys }
        (* ... error cases ... *)
      ))
      env
  ```

---

## **Phase 3: Group-By & Aggregation (Weeks 6-7)**

### **Week 6: Group-By Implementation**

#### Day 1-2: Research Arrow Group-By API
- [ ] **Review Arrow C++ group_by documentation**
  - Check garrow_table_group_by or equivalent
  - Identify aggregation functions available
  - Plan hash-based grouping strategy

#### Day 3-4: Implement Group-By C Stub
- [ ] **Add group_by C stub**
  ```c
  /* src/ffi/arrow_stubs.c - NEW FUNCTION */
  CAMLprim value caml_arrow_table_group_by(value v_ptr, value v_key_names) {
    CAMLparam2(v_ptr, v_key_names);
    CAMLlocal2(v_result, v_group_indices);
    
    GArrowTable *table = (GArrowTable *)Nativeint_val(v_ptr);
    
    // Convert OCaml string list to column indices
    int n_keys = 0;
    value iter = v_key_names;
    while (iter != Val_emptylist) {
      n_keys++;
      iter = Field(iter, 1);
    }
    
    gint *key_indices = (gint *)malloc(sizeof(gint) * n_keys);
    GArrowSchema *schema = garrow_table_get_schema(table);
    
    iter = v_key_names;
    for (int i = 0; i < n_keys; i++) {
      value head = Field(iter, 0);
      const char *key_name = String_val(head);
      key_indices[i] = garrow_schema_get_field_index(schema, key_name);
      iter = Field(iter, 1);
    }
    g_object_unref(schema);
    
    // Perform grouping
    // This is pseudo-code - actual Arrow group-by API varies
    GArrowTableGroupBy *grouped = garrow_table_group_by(table, key_indices, n_keys);
    free(key_indices);
    
    if (grouped == NULL) {
      CAMLreturn(Val_none);
    }
    
    // Return opaque handle to grouped table
    v_result = caml_alloc(1, 0);
    Store_field(v_result, 0, caml_copy_nativeint((intnat)grouped));
    CAMLreturn(v_result);
  }
  ```

- [ ] **Add external in arrow_ffi.ml**
  ```ocaml
  external arrow_table_group_by : nativeint -> string list -> nativeint option
    = "caml_arrow_table_group_by"
  ```

#### Day 5: Test Group-By
- [ ] **Create group-by test**
  ```ocaml
  (* tests/arrow_groupby_test.ml *)
  let test_groupby () =
    (* Test with sample data *)
    match Arrow_io.read_csv "tests/arrow_test.csv" with
    | Error msg -> failwith msg
    | Ok table ->
      match Arrow_ffi.arrow_table_group_by (match table.native_handle with Some h -> h.ptr | None -> failwith "No handle") ["name"] with
      | None -> failwith "Group-by failed"
      | Some _grouped_ptr ->
        print_endline "✓ Arrow group-by works"
  
  let () = test_groupby ()
  ```

---

### **Week 7: Aggregation Functions**

#### Day 1-3: Implement Aggregation C Stubs
- [ ] **Add aggregation stubs (sum, mean, count)**
  ```c
  /* src/ffi/arrow_stubs.c - NEW FUNCTIONS */
  
  CAMLprim value caml_arrow_group_sum(value v_grouped_ptr, value v_col_name) {
    CAMLparam2(v_grouped_ptr, v_col_name);
    CAMLlocal1(v_result);
    
    GArrowTableGroupBy *grouped = (GArrowTableGroupBy *)Nativeint_val(v_grouped_ptr);
    const char *col_name = String_val(v_col_name);
    
    // Compute sum per group
    GError *error = NULL;
    GArrowTable *result_table = garrow_table_group_by_aggregate(grouped, col_name, "sum", &error);
    
    if (result_table == NULL) {
      if (error) g_error_free(error);
      CAMLreturn(Val_none);
    }
    
    v_result = caml_alloc(1, 0);
    Store_field(v_result, 0, caml_copy_nativeint((intnat)result_table));
    CAMLreturn(v_result);
  }
  
  /* Similar for mean, count, min, max */
  CAMLprim value caml_arrow_group_mean(value v_grouped_ptr, value v_col_name) { ... }
  CAMLprim value caml_arrow_group_count(value v_grouped_ptr) { ... }
  ```

- [ ] **Add externals in arrow_ffi.ml**
  ```ocaml
  external arrow_group_sum : nativeint -> string -> nativeint option
  external arrow_group_mean : nativeint -> string -> nativeint option
  external arrow_group_count : nativeint -> nativeint option
  ```

#### Day 4: Update arrow_compute.ml with Aggregations
- [ ] **Add aggregation functions**
  ```ocaml
  (* src/arrow/arrow_compute.ml *)
  
  type grouped_table = {
    base_table : Arrow_table.t;
    group_handle : nativeint;
  }
  
  let group_by (t : Arrow_table.t) (keys : string list) : grouped_table =
    match t.native_handle with
    | None -> failwith "Native grouping requires Arrow backend"
    | Some handle ->
      match Arrow_ffi.arrow_table_group_by handle.ptr keys with
      | None -> failwith "Group-by failed"
      | Some group_handle ->
        { base_table = t; group_handle }
  
  let group_aggregate (grouped : grouped_table) (agg_name : string) (col_name : string) : Arrow_table.t =
    let result_ptr = match agg_name with
      | "sum" -> Arrow_ffi.arrow_group_sum grouped.group_handle col_name
      | "mean" -> Arrow_ffi.arrow_group_mean grouped.group_handle col_name
      | "count" -> Arrow_ffi.arrow_group_count grouped.group_handle
      | _ -> None
    in
    match result_ptr with
    | None -> failwith ("Aggregation failed: " ^ agg_name)
    | Some ptr ->
      (* Extract schema from result *)
      let schema_pairs = Arrow_ffi.arrow_table_get_schema ptr in
      let nrows = Arrow_ffi.arrow_table_num_rows ptr in
      let schema = List.map (fun (name, type_tag) ->
        let typ = match type_tag with
          | 0 -> Arrow_table.ArrowInt64
          | 1 -> Arrow_table.ArrowFloat64
          | 2 -> Arrow_table.ArrowBoolean
          | 3 -> Arrow_table.ArrowString
          | _ -> Arrow_table.ArrowNull
        in
        (name, typ)
      ) schema_pairs in
      Arrow_table.create_from_native ptr schema nrows
  ```

#### Day 5: Update summarize.ml
- [ ] **Use native aggregations in summarize.ml**
  ```ocaml
  (* src/packages/colcraft/summarize.ml *)
  (* This is a major refactor - need to detect when aggregation functions are simple *)
  (* and can be delegated to Arrow, vs when they need custom eval *)
  
  (* Simplified example: *)
  let register ~eval_call env =
    Env.add "summarize"
      (make_builtin ~variadic:true 1 (fun args env ->
        match args with
        | VDataFrame df :: summary_args ->
          if df.group_keys <> [] && can_use_native_agg summary_args then
            (* Use Arrow compute aggregation *)
            let grouped = Arrow_compute.group_by df.arrow_table df.group_keys in
            (* Apply aggregations... *)
            (* ... *)
          else
            (* Fall back to current manual implementation *)
            (* ... *)
      ))
      env
  ```

---

## **Phase 4: Zero-Copy Column Views (Week 8)**

### **Week 8: Bigarray Views (Optional but Recommended)**

#### Day 1-2: Implement Buffer Pointer Access
- [ ] **Add buffer pointer C stub**
  ```c
  /* src/ffi/arrow_stubs.c - NEW FUNCTION */
  CAMLprim value caml_arrow_array_get_buffer_ptr(value v_array_ptr) {
    CAMLparam1(v_array_ptr);
    CAMLlocal1(v_result);
    
    GArrowArray *array = (GArrowArray *)Nativeint_val(v_array_ptr);
    GArrowBuffer *buffer = garrow_array_get_value_data_buffer(array);
    
    if (buffer == NULL) {
      CAMLreturn(Val_none);
    }
    
    gsize size = garrow_buffer_get_size(buffer);
    const guint8 *data = garrow_buffer_get_data(buffer, &size);
    
    // Return (pointer, length)
    v_result = caml_alloc(2, 0);
    Store_field(v_result, 0, caml_copy_nativeint((intnat)data));
    Store_field(v_result, 1, Val_long(size));
    
    g_object_unref(buffer);
    CAMLreturn(v_result);
  }
  ```

- [ ] **Add external in arrow_ffi.ml**
  ```ocaml
  external arrow_array_get_buffer_ptr : nativeint -> (nativeint * int) option
    = "caml_arrow_array_get_buffer_ptr"
  ```

#### Day 3-4: Create Zero-Copy Bigarray Views
- [ ] **Implement in arrow_column.ml**
  ```ocaml
  (* src/arrow/arrow_column.ml *)
  open Bigarray
  
  type numeric_view =
    | FloatView of (float, float64_elt, c_layout) Array1.t
    | IntView of (int64, int64_elt, c_layout) Array1.t
  
  let zero_copy_view (col : column_view) : numeric_view option =
    match Arrow_table.column_type_of col.data with
    | Arrow_table.ArrowFloat64 ->
      (* Get buffer pointer from Arrow *)
      (* Create Bigarray view *)
      (* Return FloatView *)
      None (* TODO: implement *)
    | Arrow_table.ArrowInt64 ->
      None (* TODO: implement *)
    | _ -> None
  ```

#### Day 5: Document and Test
- [ ] **Write documentation for zero-copy views**
- [ ] **Create benchmark comparing copy vs zero-copy**
  ```ocaml
  (* tests/arrow_zerocopy_benchmark.ml *)
  let benchmark_copy () =
    (* Time traditional column copy *)
    (* ... *)
  
  let benchmark_zerocopy () =
    (* Time zero-copy view *)
    (* ... *)
  ```

---

## **Phase 5: Owl Integration (Week 9-10) - OPTIONAL**

### **Week 9: Owl Setup**

#### Day 1-2: Add Owl to Dependencies
- [ ] **Update flake.nix**
  ```nix
  buildInputs = [
    ocamlVersion.menhirLib
    pkgs.arrow-glib
    ocamlVersion.owl  # ADD THIS
  ];
  ```

- [ ] **Update src/dune**
  ```lisp
  (libraries menhirLib owl)
  ```

#### Day 3-5: Create arrow_owl_bridge.ml
- [ ] **Create bridge module**
  ```ocaml
  (* src/arrow/arrow_owl_bridge.ml - NEW FILE *)
  
  type owl_view = {
    backing : Arrow_table.t;
    column : string;
    arr : Owl.Arr.t;
  }
  
  let numeric_column_to_owl (table : Arrow_table.t) (col_name : string) : owl_view option =
    match Arrow_table.get_column table col_name with
    | None -> None
    | Some col ->
      match Arrow_table.column_type_of col with
      | Arrow_table.ArrowFloat64 | Arrow_table.ArrowInt64 ->
        (* Extract numeric data and create Owl array *)
        (* TODO: implement conversion *)
        None
      | _ -> None
  ```

---

### **Week 10: Update Stats Functions**

#### Day 1-3: Update lm() and cor() to Use Owl
- [ ] **Update lm.ml**
  ```ocaml
  (* src/packages/stats/lm.ml *)
  let register env =
    Env.add "lm"
      (make_builtin 3 (fun args _env ->
        match args with
        | [VDataFrame df; VString y_col; VString x_col] ->
          match (Arrow_owl_bridge.numeric_column_to_owl df.arrow_table y_col,
                 Arrow_owl_bridge.numeric_column_to_owl df.arrow_table x_col) with
          | (Some y_view, Some x_view) ->
            (* Use Owl for regression *)
            let y_arr = y_view.arr in
            let x_arr = x_view.arr in
            (* Call Owl linear regression function *)
            (* ... *)
          | _ -> failwith "Could not convert columns to Owl"
      ))
      env
  ```

#### Day 4-5: Test and Benchmark
- [ ] **Compare Owl vs manual implementation**
- [ ] **Ensure numerical accuracy**

---

## **Testing & Verification Checklist**

### **After Each Phase:**

- [ ] **Compilation Test**
  ```bash
  dune clean && dune build
  # Should compile without errors
  ```

- [ ] **Unit Tests Pass**
  ```bash
  dune test
  # All tests should pass
  ```

- [ ] **Memory Leak Check**
  ```bash
  valgrind --leak-check=full dune exec src/repl.exe -- run tests/arrow_test.t
  # Should report no leaks
  ```

- [ ] **Integration Test**
  ```bash
  # Run examples/data_analysis.t with Arrow backend
  dune exec src/repl.exe -- run examples/data_analysis.t
  # Should produce same output as before
  ```

- [ ] **Performance Benchmark**
  ```ocaml
  (* Create large CSV: 100k rows × 10 cols *)
  (* Time operations before and after Arrow *)
  ```

---

## **Final Verification (After All Phases)**

### **Complete Test Suite**
- [ ] Run all existing tests: `dune test`
- [ ] Run CI test: `dune exec src/repl.exe -- run examples/ci_test.t`
- [ ] Run data analysis example: `dune exec src/repl.exe -- run examples/data_analysis.t`
- [ ] Run pipeline example: `dune exec src/repl.exe -- run examples/pipeline_example.t`
- [ ] Run statistics example: `dune exec src/repl.exe -- run examples/statistics_example.t`

### **Performance Benchmarks**
- [ ] **Create benchmark script: tests/benchmarks/arrow_vs_pure.t**
  ```t
  -- Compare performance on large dataset (100k rows)
  print("=== Arrow Backend Performance Benchmark ===")
  
  large_df = read_csv("tests/benchmarks/large_data.csv")
  
  -- Time select operation
  -- Time filter operation  
  -- Time group_by + summarize
  -- Time arrange
  
  -- Compare to pure OCaml baseline
  ```

### **Memory Usage Verification**
- [ ] Run with large datasets (1M+ rows)
- [ ] Verify no memory leaks with valgrind
- [ ] Check that GC finalizers are working

### **Golden Test Updates**
- [ ] Update golden test outputs if needed
- [ ] Verify output equivalence

---

## **Success Criteria**

✅ **Phase 1 Complete When:**
- Can compile with Arrow C GLib linked
- Can create and free Arrow tables
- GC finalizers prevent memory leaks
- Can read CSV into native Arrow tables

✅ **Phase 2 Complete When:**
- select() and filter() use Arrow Compute kernels
- Zero-copy operations are measurably faster
- All existing colcraft tests pass

✅ **Phase 3 Complete When:**
- group_by() uses Arrow hash grouping
- summarize() delegates to Arrow aggregations
- Performance is competitive with R/Pandas

✅ **Phase 4 Complete When:**
- Zero-copy column views work for numeric types
- Bigarray views are correctly managed

✅ **Phase 5 Complete When:**
- lm() and cor() use Owl for computation
- Numerical accuracy is verified

✅ **Overall Success When:**
- **All existing tests pass** with Arrow backend
- **10x performance improvement** on large datasets (100k+ rows)
- **Zero memory leaks** (valgrind clean)
- **API compatibility** maintained (no breaking changes)

---

## **Emergency Fallback Plan**

If Arrow integration hits major blockers:

1. **Keep pure OCaml fallback** for now
2. **Move to Beta anyway** but mark Arrow as "post-Beta priority"
3. **Implement Beta language features** (pattern matching, string interpolation, lenses)
4. **Return to Arrow** once language features stabilize

This allows progress on language design while the infrastructure team tackles Arrow separately.

