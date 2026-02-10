# Performance

> Arrow backend architecture, vectorization strategy, and performance expectations

---

## Arrow Backend Architecture

T's DataFrame operations are backed by [Apache Arrow](https://arrow.apache.org/), a columnar memory format designed for efficient analytical processing. The Arrow integration provides:

- **Zero-copy column access**: Column views reference the underlying Arrow buffer directly, avoiding data copies when reading column data
- **Vectorized compute**: Arithmetic, math, and comparison operations use Arrow Compute kernels for SIMD-accelerated processing
- **Native CSV reading**: Large CSV files are parsed using Arrow C GLib's CSV reader for maximum throughput
- **Hash-based grouping**: `group_by()` operations use Arrow's hash-based grouping when a native handle is present

### Dual-Path Architecture

Every operation in T follows a **dual-path** pattern:

1. **Native Arrow path**: When the table has a `native_handle` (e.g., from `read_csv()`), operations delegate to Arrow Compute kernels via FFI for zero-copy, vectorized execution
2. **Pure OCaml fallback**: When no native handle is present (e.g., after `mutate()` materializes a table), operations use pure OCaml implementations that work on typed columnar arrays

This ensures correctness regardless of backing storage, while maximizing performance when native Arrow buffers are available.

### Zero-Copy Column Views

The `Arrow_column` module provides `column_view` and `numeric_view` types that reference the backing Arrow table without copying data:

```
┌─────────────────────────────────────────────┐
│ Arrow Table (native memory)                 │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐    │
│  │ Column A │ │ Column B │ │ Column C │    │
│  │ (Float64)│ │ (Int64)  │ │ (String) │    │
│  └──────────┘ └──────────┘ └──────────┘    │
└─────────────────────────────────────────────┘
       ↑               ↑
  FloatView ba     IntView ba
  (Bigarray)       (Bigarray)
  (zero-copy)      (zero-copy)
```

For numeric columns (`Float64`, `Int64`), `zero_copy_view` returns a Bigarray that shares memory with the Arrow buffer — no allocation or copying occurs. The GC finalizer on the backing table ensures the Arrow memory remains valid.

---

## When Vectorization Is Used vs. Fallback

| Operation | Native Arrow Path | Pure OCaml Fallback |
|-----------|-------------------|---------------------|
| `select()` (project) | Zero-copy column selection | List-based column lookup |
| `filter()` | Arrow filter kernel with bool mask | Element-wise mask application |
| `arrange()` (sort) | Arrow sort kernel | Index-based reordering |
| `add_scalar`, `multiply_scalar`, etc. | Arrow Compute arithmetic kernels | Element-wise loop |
| `sqrt`, `abs`, `log`, `exp`, `pow` | Arrow Compute unary kernels | `Array.map` with stdlib math |
| `sum`, `mean`, `min`, `max` | Arrow Compute aggregation kernels | `Array.fold_left` |
| `compare` (eq, lt, gt, le, ge) | Arrow Compute comparison kernel | Element-wise comparison |
| `group_by` | Arrow hash-based grouping | Hashtable-based grouping |
| `group_aggregate` (sum, mean, count) | Arrow group aggregation kernels | Per-group fold |

**When does the fallback trigger?**

- After `mutate()` adds or replaces a column, the table is materialized as pure OCaml (the native handle is dropped)
- After `add_column()` modifies the table structure
- When the Arrow C GLib library is not available at build time

---

## Performance Expectations by Dataset Size

The following expectations assume standard hardware (modern x86-64, 8+ GB RAM) and typical datasets with 10–20 columns:

| Operation | 10k rows | 100k rows | 1M rows |
|-----------|----------|-----------|---------|
| Column selection (`select`) | <10ms | <50ms | <500ms |
| Row filtering (`filter`) | <10ms | <100ms | <1s |
| Arithmetic operations | <20ms | <200ms | <2s |
| Aggregation (`sum`, `mean`) | <5ms | <50ms | <500ms |
| Grouping + summarization | <50ms | <500ms | <5s |
| Window functions | <30ms | <300ms | <3s |
| CSV reading | <50ms | <200ms | <2s |

Performance scales approximately linearly with row count for columnar operations. Actual timings depend on hardware, dataset characteristics (column count, string lengths, group cardinality), and whether the native Arrow path is active.

---

## Known Performance Limitations

1. **Materialization after mutate**: Adding or replacing columns materializes the entire table as pure OCaml arrays, dropping the native Arrow handle. Subsequent operations on the modified table use the fallback path. This can be significant for pipelines that alternate `mutate()` and compute-heavy operations.

2. **Single-threaded execution**: All operations run on a single thread. Arrow's multi-threaded capabilities (Rayon-based parallelism) are not yet exposed through the FFI layer.

3. **String columns**: Zero-copy views are only available for numeric columns (`Float64`, `Int64`). String column operations always copy data into OCaml heap memory.

4. **Large group counts**: Group-by with very high cardinality (>10,000 unique groups) uses O(n × g) operations in the OCaml fallback path, where n is row count and g is group count.

5. **Memory usage**: Pure OCaml fallback stores data as `option array` (boxed), using more memory than Arrow's compact nullable representation. For 1M-row datasets, expect ~2× memory overhead compared to native Arrow storage.

---

## Roadmap: Post-Alpha Performance Improvements

The following optimizations are planned for future versions:

### Beta Performance Enhancements
- Multi-threaded Arrow operations using Rayon
- Lazy evaluation with query optimization
- Column pruning for pipelines (only load needed columns)
- Predicate pushdown for filtering
- Memory-mapped file support for datasets larger than RAM
- Streaming CSV reading for incremental processing

### Long-Term Performance Goals
- GPU acceleration via Arrow CUDA
- Distributed execution (Apache Spark/Dask-like)
- Advanced query optimization (cost-based optimizer)
- Native Parquet support (faster than CSV)
- Zero-copy interop with Python/Pandas via Arrow Flight
