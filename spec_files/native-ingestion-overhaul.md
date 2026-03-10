# Specification: Native Data Ingestion Overhaul

## Overview
This document outlines the implementation plan to make **T** competitive in high-performance data benchmarks by prioritizing native Arrow-backed ingestion paths. 

Since **T** is distributed exclusively via **Nix**, we can guarantee that `arrow-glib` and `parquet-glib` are always present. The current pure OCaml CSV parser, while robust, is the primary bottleneck in benchmarks. We must transition to native readers for CSV and Parquet.

## Goals
1.  **Prioritize Native CSV**: `read_csv` should use the native Arrow CSV reader by default.
2.  **Implement Native Parquet**: Add `read_parquet` using the `parquet-glib` library.
3.  **Zero-Overhead Loading**: Ensure that reading operations return a `native_handle` immediately, avoiding the double-copy of "parsing into OCaml -> materializing into Arrow".
4.  **Strategic Fallback**: Retain the OCaml reader only for complex URL handling (pre-downloading) or as a safety fallback for malformed CSVs that the strict Arrow reader rejects.

---

## 1. Fast `read_csv` (Native by Default)

The current `read_csv` in `src/packages/dataframe/t_read_csv.ml` uses a manual OCaml line-by-line parser. This should be refactored into a "Try Native First" strategy.

### Workflow:
1.  **URL Handling**: If the path is a URL, use `Arrow_io.download_url` to fetch it to a temporary local file.
2.  **Native Attempt**: Call `Arrow_ffi.read_csv` (which uses `GArrowCSVReader`).
3.  **Result Conversion**:
    *   If successful, return a `VDataFrame` with a `native_handle`. The schema should be extracted via `caml_arrow_table_get_schema`.
    *   If unsuccessful (e.g., column count mismatch or type inference failure), log a warning and fall back to the OCaml parser.
4.  **Remove Materialization Layer**: The native reader already produces an Arrow table; do **not** convert it to OCaml values unless explicitly requested (e.g., by a row-wise operation).

---

## 2. Implementing `read_parquet`

Since `parquet-glib` is available in the environment, we will add support for Parquet files.

### C FFI (src/ffi/arrow_stubs.c):
Add `caml_arrow_read_parquet` to the stubs:
```c
/* Pseudocode */
GArrowTable *table = gparquet_arrow_file_reader_read_table(reader, &error);
```

### OCaml Bindings (src/arrow/arrow_ffi.ml):
```ocaml
external arrow_read_parquet : string -> nativeint option = "caml_arrow_read_parquet"
```

### User Facing (src/packages/dataframe/t_read_parquet.ml):
Implement standard `read_parquet(path)` function.

---

## 3. Performance & Memory Management

### Avoiding Materialization Debt
A common mistake currently in **T** is:
1.  Read CSV into OCaml lists of lists.
2.  Convert lists to OCaml arrays.
3.  Call `Arrow_bridge.table_from_value_columns`.
4.  Inside bridge, call `materialize` which copies OCaml strings/floats into the C heap.

**The New Target**:
1.  `read_parquet` / `read_csv` (native) -> `GArrowTable*` in C heap.
2.  Wrap pointer in `native_handle` in OCaml.
3.  **Zero copies performed.** The data stays in the C heap until a computation (like `sum` or `filter`) is triggered.

### Garbage Collection
All native ingestion paths must register their pointers using `Arrow_table.register_finalizer` to prevent memory leaks in long-running benchmark loops.

---

## 4. Benchmark Preparation
Once implemented, the benchmark suite should be updated:
*   Ensure R/Python use their respective native parquet/arrow readers.
*   Update T scripts to use `read_parquet` (if available) or `read_csv` (now native).
*   Verify that T is performing the "Reading" phase in sub-second time for million-row datasets.

---

## 5. Summary Table

| Format | Old Path (Slow) | New Path (Fast) | Tech |
| :--- | :--- | :--- | :--- |
| **CSV** | OCaml String Split | `GArrowCSVReader` | Native C |
| **Parquet** | Not Supported | `GParquetArrowReader` | Native C |
| **Arrow IPC** | `read_arrow` (Existing) | `read_arrow` (Existing) | Native C |
| **URL** | Download -> OCaml Parse | Download -> Native Parse | Both |
