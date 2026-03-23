# Strategic Design Document: Numerical Backend Strategy for the T Programming Language

**Version:** 2.0  
**Last Updated:** February 2026  
**Status:** Implementation Ready

---

## Executive Summary

This document defines the numerical and statistical backend architecture for **T**, an OCaml-based programming language for data science. The architecture uses a **layered, tool-appropriate approach**:

- **Apache Arrow** for heterogeneous tabular operations (DataFrame verbs)
- **Owl** for homogeneous numeric operations (matrix math, ML)
- **GSL** (via FFI) for specialized statistical functions

**Key Principle:** Minimize data movement. Most operations stay within their native layer, with conversions only when crossing computational domains.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [The Heterogeneous Data Challenge](#the-heterogeneous-data-challenge)
3. [Decision Matrix: When to Use What](#decision-matrix)
4. [Memory Management Strategy](#memory-management)
5. [Module Structure](#module-structure)
6. [Performance Characteristics](#performance-characteristics)
7. [Implementation Priorities](#implementation-priorities)
8. [Worked Examples](#worked-examples)
9. [References](#references)

---

## Architecture Overview

T's numerical stack consists of three specialized layers, each optimized for different computational patterns:

### Layer 1: Tabular Operations (Apache Arrow)

**Purpose:** Heterogeneous tabular data manipulation  
**Memory Layout:** Columnar (column-oriented)  
**Data Model:** Mixed types per column (String, Int, Float, Bool, NA)  
**Performance:** Zero-copy slicing, cache-friendly analytics  

**Operations:**
- DataFrame verbs: `select`, `filter`, `mutate`, `arrange`
- Grouping and aggregation: `group_by`, `summarize`
- Joins and set operations
- Column-wise arithmetic
- Basic reductions: `sum`, `mean`, `count`, `min`, `max`

**Why Arrow:** 
- Designed for heterogeneous data (strings, mixed types, nulls)
- Efficient columnar layout for analytical queries
- Industry-standard format (interop with Python, R, Spark)
- Built-in compute kernels for common operations

### Layer 2: Numeric Operations (Owl)

**Purpose:** Homogeneous numeric computation  
**Memory Layout:** Row-major dense arrays (contiguous memory)  
**Data Model:** Numeric matrices (Float64, Int64)  
**Performance:** Optimized for linear algebra (BLAS/LAPACK)  

**Operations:**
- Linear algebra: QR, SVD, Cholesky, eigendecomposition
- Matrix operations: multiplication, inversion, factorization
- Statistical modeling: linear regression, PCA, clustering
- Optimization: gradient descent, L-BFGS
- Automatic differentiation

**Why Owl:**
- Pure OCaml with functional API
- Minimal unsafe FFI during development
- Rich ecosystem for scientific computing
- Well-suited for T's functional design

### Layer 3: Specialized Functions (GSL via FFI)

**Purpose:** Statistical functions not in Owl  
**Implementation:** Direct C bindings (isolated module)  

**Operations:**
- Probability distributions (sampling, PDF, CDF)
- Special functions (gamma, beta, erf)
- Random number generation
- Advanced time series (ARIMA)
- Non-linear optimization (when Owl insufficient)

**Why GSL:**
- Comprehensive statistical function library
- Battle-tested implementations
- Performance-critical edge cases

---

## The Heterogeneous Data Challenge

### Core Problem

DataFrames are **fundamentally heterogeneous**. A typical DataFrame might look like:

```ocaml
DataFrame {
  name: ["Alice", "Bob", "Charlie"],      (* String column *)
  age: [30, 25, 35],                      (* Int64 column *)
  score: [95.5, 87.3, NA],                (* Float64 column with missing values *)
  active: [true, false, true]             (* Boolean column *)
}
```

**Owl cannot represent this.** Owl operates on homogeneous numeric matrices where every element has the same type.

### Solution: Keep Data in Its Native Representation

**Don't convert unless you must.**

```
DataFrame operations → Stay in Arrow (columnar, heterogeneous)
Numeric operations   → Extract numeric columns → Owl (homogeneous)
Results              → Stay small or convert back to Arrow
```

---

## Decision Matrix

Use this table to determine which layer handles each operation:

| Operation Category | Layer | Rationale |
|-------------------|-------|-----------|
| **DataFrame Verbs** | | |
| `select(cols)` | Arrow | Columnar projection (zero-copy) |
| `filter(predicate)` | Arrow | Arrow Compute filter kernel |
| `mutate(new_col = expr)` | Arrow | Arrow Compute expression evaluation |
| `arrange(col)` | Arrow | Arrow Compute sort kernel |
| `group_by(keys) + summarize(agg)` | Arrow | Arrow Compute group-aggregate kernels |
| **Column Operations** | | |
| `df.age + 1` | Arrow | Vectorized arithmetic kernel |
| `df.score * 2.5` | Arrow | Type-preserving numeric ops |
| `mean(df.age)` | Arrow | Arrow Compute mean kernel |
| `sum(df.values)` | Arrow | Arrow Compute sum kernel |
| **Statistical Modeling** | | |
| `lm(y ~ x)` | Owl | Extract numeric cols → regression |
| `cor(x, y)` | Owl | Covariance calculation |
| `pca(data)` | Owl | SVD/eigendecomposition |
| **Matrix Operations** | | |
| `matrix_multiply(A, B)` | Owl | BLAS-backed matrix ops |
| `svd(matrix)` | Owl | Numeric linear algebra |
| `cholesky(cov_matrix)` | Owl | Matrix factorization |
| **Distributions** | | |
| `rnorm(n, mean, sd)` | GSL | Sampling from normal distribution |
| `dnorm(x, mean, sd)` | GSL | Normal PDF evaluation |
| `qgamma(p, shape, scale)` | GSL | Inverse CDF (quantile function) |

### Decision Flow

```
┌─────────────────────────────────────┐
│ Is this a DataFrame verb?           │
│ (select/filter/mutate/group_by)     │
└──────────┬──────────────────────────┘
           │
       YES │                    NO
           ▼                     │
    ┌──────────────┐            │
    │ Use Arrow    │            │
    │ Compute      │            │
    └──────────────┘            │
                                 │
                    ┌────────────▼────────────┐
                    │ Does it operate on      │
                    │ heterogeneous columns?  │
                    └────────┬────────────────┘
                             │
                         YES │            NO
                             ▼             │
                      ┌────────────┐      │
                      │ Use Arrow  │      │
                      │ (stay      │      │
                      │ columnar)  │      │
                      └────────────┘      │
                                          │
                             ┌────────────▼────────────┐
                             │ Is it a matrix/ML op?   │
                             └────────┬────────────────┘
                                      │
                                  YES │            NO
                                      ▼             │
                               ┌─────────────┐     │
                               │ Extract     │     │
                               │ numeric     │     │
                               │ columns     │     │
                               │ → Owl       │     │
                               └─────────────┘     │
                                                    │
                                       ┌────────────▼────────┐
                                       │ Is it a special     │
                                       │ statistical func?   │
                                       └────────┬────────────┘
                                                │
                                            YES │        NO
                                                ▼         │
                                         ┌─────────┐     │
                                         │ GSL FFI │     │
                                         └─────────┘     │
                                                          │
                                                          ▼
                                                   ┌──────────┐
                                                   │ Error:   │
                                                   │ No impl  │
                                                   └──────────┘
```

---

## Memory Management Strategy

### Arrow Table Lifetime

Arrow tables are C++ objects managed via OCaml finalizers:

```ocaml
(* arrow_table.ml *)
type t = {
  ptr : nativeint;          (* Pointer to C++ Arrow::Table *)
  schema : schema;          (* Column names and types *)
  nrows : int;              (* Cached row count *)
}

(* Register GC finalizer when creating table *)
let create ptr schema nrows =
  let table = { ptr; schema; nrows } in
  Gc.finalise (fun t -> arrow_table_free t.ptr) table;
  table

external arrow_table_free : nativeint -> unit = "caml_arrow_table_free"
```

### Zero-Copy Views: Arrow → Owl

For **numeric columns with compatible layout**, create zero-copy views:

```ocaml
(* arrow_owl_bridge.ml *)
type owl_view = {
  backing : Arrow_table.t;     (* Keep Arrow table alive *)
  column : string;              (* Which column *)
  arr : Owl.Arr.t;             (* Bigarray view into Arrow buffer *)
}

let numeric_column_view (table : Arrow_table.t) (col_name : string) : owl_view option =
  match Arrow_table.column_type table col_name with
  | Some Float64 | Some Int64 ->
      (* Get pointer to Arrow buffer *)
      let buf_ptr = arrow_get_column_buffer table.ptr col_name in
      let buf_len = table.nrows in
      
      (* Create bigarray view (no copy!) *)
      let arr = Bigarray.Array1.of_ptr 
                  Bigarray.float64 
                  Bigarray.c_layout 
                  buf_ptr 
                  buf_len in
      
      Some { backing = table; column = col_name; arr = Owl.Arr.of_bigarray arr }
  
  | _ -> None  (* Non-numeric or incompatible layout *)
```

**Critical:** The `backing` field keeps the Arrow table alive via GC. When `owl_view` is collected, Arrow table can be freed.

### When Copying is Necessary

Copy data when:
1. **Type conversion required** (Int32 → Float64)
2. **Layout incompatible** (Arrow nullable column → Owl dense array)
3. **Missing values present** (must be handled explicitly)

```ocaml
(* arrow_owl_bridge.ml *)
let numeric_column_copy (table : Arrow_table.t) (col_name : string) 
    : (Owl.Mat.mat, error) result =
  
  let col = Arrow_table.get_column table col_name in
  match col with
  | Float64_column values ->
      (* Check for NAs *)
      if Array.exists is_na values then
        Error (make_error TypeError "Cannot convert column with NAs to Owl. Handle missingness first.")
      else
        (* Copy to Owl matrix *)
        let data = Array.map float_of_value values in
        Ok (Owl.Mat.of_array data 1 (Array.length data))
  
  | _ -> Error (make_error TypeError "Column is not numeric")
```

---

## Module Structure

### Recommended File Layout

```
src/
├── arrow/
│   ├── arrow_table.ml         # DataFrame type, memory management, GC
│   ├── arrow_compute.ml       # OCaml wrappers for Arrow Compute kernels
│   │                          # - select, filter, group_by, aggregate
│   │                          # - column arithmetic, comparisons
│   ├── arrow_io.ml            # CSV/Parquet reading/writing
│   └── arrow_owl_bridge.ml    # Numeric column extraction
│                              # - Zero-copy views when possible
│                              # - Explicit copy with NA handling
│
├── numeric/
│   ├── owl_wrappers.ml        # Statistical modeling using Owl
│   │                          # - lm(), cor(), pca(), clustering
│   └── owl_utils.ml           # Helper functions for Owl operations
│
├── ffi/
│   ├── gsl_bindings.ml        # C bindings to GSL
│   │                          # - Distributions (rnorm, dnorm, etc.)
│   │                          # - Special functions (gamma, beta)
│   └── gsl_stubs.c            # C wrapper functions for GSL
│
└── packages/
    ├── colcraft/              # DataFrame verbs → arrow_compute
    │   ├── select.ml          # Calls Arrow_compute.select
    │   ├── filter.ml          # Calls Arrow_compute.filter
    │   ├── mutate.ml          # Calls Arrow_compute.mutate
    │   ├── group_by.ml        # Calls Arrow_compute.group_by
    │   └── summarize.ml       # Calls Arrow_compute.aggregate
    │
    ├── stats/                 # Statistical functions → owl_wrappers
    │   ├── mean.ml            # Arrow_compute for simple case
    │   ├── sd.ml              # Arrow_compute or Owl depending on context
    │   ├── cor.ml             # Extract columns → Owl
    │   └── lm.ml              # Extract columns → Owl regression
    │
    └── math/                  # Pure functions
        ├── sqrt.ml            # Pure OCaml (or Arrow vectorized)
        ├── log.ml             # Pure OCaml
        └── distributions.ml   # GSL bindings
```

### C FFI Modules

```
src/ffi/arrow_c_api.c         # C wrappers for Arrow C GLib
src/ffi/arrow_stubs.c         # OCaml-to-C bridge for Arrow
src/ffi/gsl_stubs.c           # OCaml-to-C bridge for GSL
```

---

## Performance Characteristics

### Expected Latencies (1M rows × 10 columns)

| Operation | Layer | Expected Time | Notes |
|-----------|-------|---------------|-------|
| **select(2 cols)** | Arrow | <1ms | Zero-copy column slicing |
| **filter(age > 25)** | Arrow | ~10ms | Vectorized comparison + selection |
| **mutate(new = a + b)** | Arrow | ~15ms | Vectorized add, new column allocation |
| **group_by + mean** | Arrow | ~50ms | Hash-based grouping + reduction |
| **arrange(col)** | Arrow | ~80ms | Radix sort for numeric, comparison sort for strings |
| **mean(column)** | Arrow | ~5ms | Single-pass reduction |
| **lm(y ~ x)** | Owl | ~100ms | Extraction (20ms) + computation (80ms) |
| **pca(matrix)** | Owl | ~200ms | Extraction + SVD |
| **join(left, right)** | Arrow | ~150ms | Hash join |

### Bottlenecks to Avoid

❌ **Anti-pattern:** Converting entire DataFrame to Owl for a simple filter
```ocaml
(* SLOW: Converts all columns to Owl, filters, converts back *)
df |> to_owl |> owl_filter predicate |> to_arrow
```

✅ **Correct:** Stay in Arrow
```ocaml
(* FAST: Arrow Compute filter kernel *)
df |> Arrow_compute.filter predicate
```

❌ **Anti-pattern:** Converting to Owl for column arithmetic
```ocaml
(* SLOW: Unnecessary conversion *)
df.age |> arrow_to_owl |> Owl.Arr.add_scalar 1.0 |> owl_to_arrow
```

✅ **Correct:** Arrow vectorized operations
```ocaml
(* FAST: Arrow Compute kernel *)
df |> mutate("age_plus_1", \(row) row.age + 1)
```

### Memory Usage Patterns

| Operation | Arrow Layer | Owl Layer | Total |
|-----------|-------------|-----------|-------|
| **Simple filter** | 1× (original) | 0× | 1× |
| **Mutate (new column)** | 1.1× (one new col) | 0× | 1.1× |
| **Group-by-mean** | 1× + small indices | 0× | ~1.01× |
| **Linear regression** | 1× (original) | 0.2× (2 cols copied) | 1.2× |
| **PCA (all columns)** | 1× (original) | 1× (full copy) | 2× |

---

## Implementation Priorities

### Phase 1: Arrow Basics (Week 1-2)

**Goal:** DataFrame operations stay in Arrow

**Tasks:**
1. ✅ Implement `Arrow_table.t` type with GC finalizers
2. ✅ Wrap Arrow C GLib API for table creation
3. ✅ Implement `read_csv()` → Arrow table
4. ✅ Implement column accessors (dot notation)
5. ✅ Test memory management (no leaks)

**Deliverable:** Can load CSV, access columns, no crashes

### Phase 2: Arrow Compute (Week 3-4)

**Goal:** DataFrame verbs use Arrow Compute kernels

**Tasks:**
1. ✅ Wrap Arrow Compute filter kernel → `Arrow_compute.filter`
2. ✅ Wrap Arrow Compute projection → `Arrow_compute.select`
3. ✅ Wrap Arrow Compute scalar kernels → `Arrow_compute.add`, `sub`, etc.
4. ✅ Implement `mutate()` using Arrow expression evaluation
5. ✅ Implement `arrange()` using Arrow sort kernel

**Deliverable:** Basic tidyverse-style pipelines work

### Phase 3: Arrow Grouping (Week 5-6)

**Goal:** Group-by and aggregation in Arrow

**Tasks:**
1. ✅ Wrap Arrow Compute group-by kernel
2. ✅ Implement `group_by()` → grouped DataFrame handle
3. ✅ Implement `summarize()` with Arrow aggregate functions
4. ✅ Support multiple aggregations per group

**Deliverable:** Split-apply-combine patterns work

### Phase 4: Owl Integration (Week 7-8)

**Goal:** Numeric operations bridge to Owl

**Tasks:**
1. ✅ Implement `arrow_owl_bridge.ml`
2. ✅ Zero-copy views for compatible numeric columns
3. ✅ Explicit copy path with NA error handling
4. ✅ Implement `lm()` using Owl regression
5. ✅ Implement `cor()`, `pca()` using Owl

**Deliverable:** Statistical modeling works

### Phase 5: GSL Bindings (Week 9-10)

**Goal:** Distribution functions via GSL

**Tasks:**
1. ✅ Write C stubs for GSL functions
2. ✅ Implement `rnorm()`, `dnorm()`, `qnorm()`
3. ✅ Implement other distribution families
4. ✅ Test numerical accuracy

**Deliverable:** Full statistical function library

---

## Worked Examples

### Example 1: Filter and Select (Stay in Arrow)

```ocaml
(* T code *)
df |> filter(\(row) row.age > 25)
   |> select("name", "score")

(* Implementation *)
let eval_filter df predicate =
  (* Build Arrow Compute expression from predicate *)
  let arrow_expr = compile_predicate_to_arrow predicate in
  
  (* Call Arrow Compute filter kernel (zero-copy where possible) *)
  Arrow_compute.filter df.table arrow_expr
  |> Arrow_table.wrap

let eval_select df cols =
  (* Call Arrow Compute projection (zero-copy) *)
  Arrow_compute.project df.table cols
  |> Arrow_table.wrap

(* Result: No data copied, purely columnar operations *)
```

### Example 2: Linear Regression (Bridge to Owl)

```ocaml
(* T code *)
model = lm(df, "score", "age")

(* Implementation *)
let eval_lm df y_col x_col =
  (* Extract numeric columns to Owl *)
  let y = Arrow_owl_bridge.numeric_column_copy df y_col in
  let x = Arrow_owl_bridge.numeric_column_copy df x_col in
  
  match (y, x) with
  | (Ok y_mat, Ok x_mat) ->
      (* Run Owl regression *)
      let model = Owl_wrappers.linear_regression y_mat x_mat in
      
      (* Return model as T Dict *)
      VDict [
        ("intercept", VFloat model.intercept);
        ("slope", VFloat model.slope);
        ("r_squared", VFloat model.r_squared);
      ]
  
  | (Error e, _) | (_, Error e) -> e

(* Result: Minimal data copied (2 columns), stays in Owl for compute *)
```

### Example 3: Group-by with Mean (Stay in Arrow)

```ocaml
(* T code *)
df |> group_by("dept") 
   |> summarize("avg_score", \(g) mean(g.score))

(* Implementation *)
let eval_group_by df keys =
  (* Call Arrow Compute hash_group_by *)
  let groups = Arrow_compute.group_by df.table keys in
  { df with groups = Some groups }

let eval_summarize grouped_df agg_exprs =
  match grouped_df.groups with
  | Some groups ->
      (* For each aggregation, call Arrow Compute aggregate kernel *)
      let results = List.map (fun (name, expr) ->
        match expr with
        | MeanExpr col -> 
            Arrow_compute.group_mean groups col
        | SumExpr col ->
            Arrow_compute.group_sum groups col
        | _ -> (* ... *)
      ) agg_exprs in
      
      (* Results stay in Arrow *)
      Arrow_table.from_aggregate results
  
  | None -> error "summarize() requires grouped DataFrame"

(* Result: All computation in Arrow Compute kernels, no Owl conversion *)
```

---

## References

### Libraries

- **Apache Arrow:** https://arrow.apache.org/docs/
  - C GLib API: https://arrow.apache.org/docs/c_glib/
  - Compute Kernels: https://arrow.apache.org/docs/cpp/compute.html

- **Owl Numerical Library:** https://ocaml.xyz/
  - API Documentation: https://ocaml.xyz/owl/
  - Tutorial: https://ocaml.xyz/book/

- **GNU Scientific Library (GSL):** https://www.gnu.org/software/gsl/
  - Manual: https://www.gnu.org/software/gsl/doc/html/

### OCaml FFI Resources

- **OCaml Manual - Interfacing C with OCaml:** https://ocaml.org/manual/intfc.html
- **Real World OCaml - Foreign Function Interface:** https://dev.realworldocaml.org/foreign-function-interface.html
- **ctypes Library:** https://github.com/ocamllabs/ocaml-ctypes

### Related Projects

- **Arrow OCaml Bindings:** Limited, may need custom wrappers
- **Owl-DataFrame:** Experimental, not mature enough
- **OCaml-GSL:** Existing bindings we can leverage

---

## Appendix A: Type Conversions

### Arrow → Owl (Numeric Columns Only)

| Arrow Type | Owl Type | Zero-Copy? | Notes |
|------------|----------|------------|-------|
| Float64 | `float Bigarray.t` | ✅ Yes | Direct memory view |
| Int64 | `float Bigarray.t` | ❌ No | Must convert int→float |
| Int32 | `float Bigarray.t` | ❌ No | Must convert + widen |
| Float64 (with nulls) | - | ❌ No | Must handle NAs explicitly |

### Owl → Arrow (Return Values)

Most Owl operations return small results (scalars, small matrices):
- Regression coefficients: 2-10 floats
- PCA components: k×n matrix (k << n usually)
- Correlations: Scalar or matrix

**Strategy:** Convert Owl results to T values directly (VFloat, VDict), not back to Arrow tables.

---

## Appendix B: Error Handling

### NA Handling at Boundaries

**Rule:** Arrow supports nulls natively. Owl does not.

```ocaml
(* When extracting column for Owl *)
let extract_numeric_column df col =
  let arrow_col = Arrow_table.get_column df col in
  
  (* Check for nulls *)
  if Arrow_column.has_nulls arrow_col then
    Error (make_error TypeError 
      "Cannot convert column with NAs to Owl. Use filter() or fill_na() first.")
  else
    (* Safe to convert *)
    Ok (Arrow_owl_bridge.to_owl_array arrow_col)
```

**User guidance:** Provide clear error messages that explain how to fix:
```
Error(TypeError: "Column 'age' contains NA values and cannot be used in 
  lm(). Filter them out first:
  
  df |> filter(\(row) not is_na(row.age)) |> lm('score', 'age')
  
  or use fill_na():
  
  df |> mutate('age', \(row) if is_na(row.age) mean(df.age) else row.age)")
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | Jan 2026 | Initial | First draft |
| 2.0 | Feb 2026 | Revision | Complete rewrite addressing heterogeneous data, memory management, and layer separation |

---

**This document is implementation-ready. Engineers should refer to this as the authoritative specification when implementing T's numerical backend.**
