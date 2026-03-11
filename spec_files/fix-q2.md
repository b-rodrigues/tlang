# Brainstorming: Optimizing Grouped Aggregations (Q2)

The `q2` query in the NYC Taxi benchmark is currently significantly slower in T (~43s) compared to Python/R (<1s). This document outlines the identified bottlenecks and proposes a plan to fix them.

## Identified Bottlenecks

### 1. Unconditional OCaml Grouping
In `src/arrow/arrow_compute.ml`, the `group_by` function currently calls `group_by_ocaml` unconditionally, even when a native Arrow handle is present.
- **Problem**: `group_by_ocaml` iterates over every row (3 million in NYC Taxi) and performs string concatenation and hash table lookups in OCaml.
- **Impact**: Adds ~30-40 seconds of overhead to every grouped operation on large datasets.

### 2. Redundant Chunk Lookups in FFI
The native aggregation functions (e.g., `caml_arrow_group_mean` in `src/ffi/arrow_stubs.c`) use `get_numeric_value` for every row in every group.
- **Problem**: `get_numeric_value` performs a full chunk lookup (`garrow_chunked_array_get_chunk`) for every call.
- **Impact**: Results in $O(N \times C)$ complexity where $N$ is rows and $C$ is number of chunks. For a 3M row table with dozens of chunks, this is extremely slow.

### 3. Limited Type Support in Native Aggregations
`get_numeric_value` currently only handles `INT64` and `DOUBLE` types.
- **Problem**: If the target column is `INT32` or `FLOAT32` (common in NYC Taxi data), the native aggregation fails and falls back to even slower OCaml processing.

### 4. Lack of Vectorized Row Counting
While `nrow()` was recently added to the optimizer, it might not be used optimally in all grouped contexts.

## Proposed Fixes

### Phase 1: Lazy Grouping and FFI Optimization
1.  **Make `group_by` Lazy**: Modify `Arrow_compute.grouped_table` to make `ocaml_groups` an `option ref`. Populate it only when `group_aggregate_ocaml` is actually called.
2.  **Optimize `caml_arrow_group_mean/sum`**:
    - Pre-fetch the target column's `GArrowChunkedArray` once.
    - Implement a "chunk cache" or use a sequential iterator to access row values without re-scanning chunks from the beginning.
3.  **Expand `get_numeric_value` Types**: Add support for `INT32`, `UINT32`, `INT16`, and `FLOAT32` to the native aggregation path.

### Phase 2: Native Arrow Kernels
Instead of manually iterating over groups in C, we should transition to using Arrow's own `hash_aggregate` kernels if possible.
- **Challenge**: Arrow C GLib's support for hash aggregations is less mature than the C++ API. 
- **Alternative**: If GLib doesn't expose it well, continue optimizing the manual C iteration but ensure it's as zero-copy as possible.

### Phase 3: OCaml Optimization
For cases where fallback is unavoidable:
- Use `Zlib`-based hashing or specialized integer hash maps in OCaml instead of `Hashtbl` with string keys.
- Avoid `value_to_string` in the hot loop of `group_by_ocaml`.

## Expected Impact
- Eliminating the unconditional OCaml `group_by` should immediately save ~30-40 seconds on the `q2` benchmark.
- Optimizing C chunk lookups should bring the native aggregation time from seconds down to milliseconds.
- Overall, `q2` should run in < 1 second, matching Python and R performance.
