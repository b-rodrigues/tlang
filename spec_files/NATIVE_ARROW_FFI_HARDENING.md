# Hardening the Native Arrow FFI and Pipeline Stability

> **Date**: 2026-03-09  
> **Committed since**: `9a85f864e86a869948cadc062d228719eac9a4b2`  
> **Branch**: `fix-arrow-tests`  

## Overview

Following the recommendations in `spec_files/ALPHA_RELEASE_FINDINGS.md`, we initiated a series of hardening passes on the native Arrow FFI layer and the T-Pipeline integration. These changes were triggered by several critical issues uncovered during end-to-end pipeline Stress tests, particularly related to memory safety (segmentation faults) and the preservation of the "fast path" (native Arrow handles).

## 1. Problems Identified

### A. Pipeline Segmentation Faults (Stale Pointers)
The most critical issue was a non-deterministic segmentation fault during Nix builds of pipeline nodes.  
**Root Cause**: Native Arrow DataFrames were being serialized to disk using OCaml's `Marshal`. `Marshal` copies the raw `nativeint` (pointer) to the GArrowTable. In subsequent pipeline nodes (separate Nix processes), these pointers were invalid (stale), leading to memory corruption and crashes when the FFI attempted to deregister or use them.

### B. FFI Stack Corruption in `caml_arrow_table_new`
The `caml_arrow_table_new` function, used to rebuild native tables from OCaml data, had several safety flaws.  
**Root Cause**: Incorrect placement of `CAMLlocal` macros and missing `CAMLparam/CAMLreturn` hygiene in complex loops caused stack corruption. Additionally, a missing reference to `v_res` (result variable) led to GC-unsafe behavior.

### C. Resource Leaks and Missing NULL Checks
**Root Cause**: Several FFI calls (like `garrow_chunked_array_get_chunk`) were assumed to always succeed. In edge cases (like empty tables or memory pressure), they could return `NULL`, which was then dereferenced. Also, some strings returned by the GLib layer were not properly freed with `g_free`.

### D. Silent Fallback (Native Path Loss)
**Root Cause**: De-facto "standard" transformations like `rename` or `mutate` were dropping the `native_handle` by default, forcing the entire subsequent pipeline onto the OCaml fallback path. This made the performance claims in `docs/performance.md` difficult to maintain in realistic usage.

### E. Native-Backed Empty Table KeyErrors
**Root Cause**: For 0-row tables, the Arrow FFI might return `None` for a column chunk. The OCaml wrapper `get_column` interpreted this as "column not found," causing a `KeyError` even if the column existed in the schema.

---

## 2. Solutions Implemented

### A. Serialization Protection (`src/arrow/arrow_bridge.ml`)
We introduced **Recursive Materialization**. Before any T value is serialized to disk (e.g., in a pipeline node output), it now passes through `prepare_value_for_serialization`. This function:
1. Detects `VDataFrame` values.
2. Calls `Arrow_table.prepare_for_serialization`.
3. Ensures all column data is copied to OCaml heaps and the `native_handle` is wiped.
4. **Outcome**: Pointers never hit the disk; subsequent nodes always rebuild their own native handles safely.

### B. FFI Robustification (`src/ffi/arrow_stubs.c`)
1. **Safety**: Moved all `CAMLlocal` declarations to the top of functions to ensure they cover the entire scope.
2. **Defensive Programming**: Added explicit `NULL` checks for every GLib/Arrow pointer returned before wrapping it in OCaml `Some`.
3. **Memory Hygiene**: Added `g_free` for string copies and ensured `GError` cleanup on all failure paths.
4. **Hygiene**: Corrected `caml_arrow_table_new` to use standard `CAMLparam/CAMLreturn` flows and unified `v_res` management.

### C. Handle Preservation & Visibility
1. **Preservation**: Re-enabled and stabilized materialization in `rename_columns` and `table_from_value_columns`. If the schema is compatible, T now proactively rebuilds the native Arrow backend.
2. **Explain Visibility** (`src/packages/explain/t_explain.ml`): Added `storage_backend` ("native_arrow" vs "pure_ocaml") and `native_path_active` (bool) to the `explain(df)` dictionary. This allows users and tests to verify if the "fast path" is active.
3. **NSE Support**: Fixed a bug where `explain(df)` failed if the DataFrame was inside a pipeline node involving NSE.

### D. Empty Table Robustness (`src/arrow/arrow_table.ml`)
Modified `get_column` to detect the "Empty Table + Missing Chunk" case. If the table has 0 rows, it now returns an empty OCaml column of the correct type (based on schema) instead of `None`.

---

## 3. Comparison to `ALPHA_RELEASE_FINDINGS.md`

The work performed since commit `9a85f864` addresses two major areas identified as Alpha blockers:

| Finding ID | Finding Description | Resolution in these Commits |
|:---|:---|:---|
| **#1** | Native Arrow validation in CI | Added `Arrow mutate keeps native path active` to `test_arrow_integration.ml`. Ensured pipeline E2E tests exercise the native path. |
| **#5** | Clarify "fast path vs fallback" | Added Backend status (storage_backend) to `explain()`. Documented visibility in `docs/performance.md`. |
| **Release Hardening** | Stability & User Journey | Fixed the critical Nix pipeline segfault that would have blocked the successful execution of any real-world pipeline. |

## 4. Current Status

- **Tests Passing**: `tests/arrow/test_arrow_integration.ml` passes all 10 checks.
- **Pipeline Stable**: `tests/pipeline/test_pipeline_e2e.t` builds and runs successfully in the Nix environment without segfaults.
- **Ready for Alpha**: The core data engine is now significantly more robust for cross-process usage.
