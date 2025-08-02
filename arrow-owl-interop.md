# Strategic Design Document: Numerical Backend Strategy for the T Programming Language

## Purpose

This document outlines the strategic approach for implementing the numerical and statistical backend of **T**, a programming language for data science built in OCaml. It is intended to guide decisions among co-authors and contributors regarding library choices and implementation strategy.

## Guiding Principles

1. **Fast and focused development**: Prioritize rapid prototyping and a productive OCaml-native workflow.
2. **High-level usability**: T's user-facing interface should be intuitive and high-level, akin to R or Python's tidyverse.
3. **Performance through reuse**: Leverage high-performance, well-maintained libraries wherever possible.
4. **Safe by default**: Minimize unsafe bindings and imperative FFI code unless absolutely necessary.

## Architecture Overview

T's numerical stack is structured in three layers:

* **Tabular Layer**: Powered by \[Apache Arrow], providing an efficient columnar memory layout and cross-language interoperability. T's `DataFrame` type wraps Arrow tables.

* **Compute Layer**: Powered primarily by the \[Owl] library, which provides matrix operations, linear algebra, optimization, and machine learning in OCaml.

* **Fallback Layer**: Selectively use C bindings to \[GSL], \[LAPACK], or other libraries when Owl is insufficient (e.g., for distributions, ARIMA models, or fine-grained control).

## Why Owl as Primary Backend

Owl is chosen as the primary computational backend for the following reasons:

### ✅ Developer Productivity

* Written in OCaml, with minimal C glue.
* Functional, expressive APIs that align well with the T language philosophy.
* Avoids boilerplate and unsafe FFI code during early-stage development.

### ✅ Rich Functionality

* Linear algebra (QR, SVD, Cholesky, eigendecomposition)
* Optimization (gradient descent, L-BFGS)
* Machine learning (logistic regression, k-means, basic NNs)
* Automatic differentiation (via Algodiff)

### ✅ Good Enough Performance

* Backed by OpenBLAS or LAPACK internally.
* Suitable for small to medium data tasks typical in data science workflows.

### ✅ Clean Interoperability

* Easy to wrap into T verbs (e.g., `lm`, `pca`, `summarize`)
* Compatible with pure OCaml values for integration with the rest of the standard library.

## When to Use Direct C Bindings

Direct bindings to GSL or LAPACK should be considered when:

* Owl lacks required functionality (e.g., sampling from distributions)
* Low-level control over memory layout or algorithm parameters is essential
* Performance for very large datasets becomes a bottleneck

These bindings should be encapsulated in a separate, isolated module (e.g., `ffi_fallback.ml`) to maintain a clear boundary and minimize unsafe code.

## Proposed Modules

* `arrow_bridge.ml` — Converts between Arrow tables and Owl/Numerical types.
* `owl_backend.ml` — Pure OCaml wrappers around Owl's functionality.
* `ffi_fallback.ml` — Selective C bindings for advanced features not covered by Owl.

## Summary

T’s architecture leverages Owl for most numerical and ML tasks, balancing productivity and power. Arrow handles tabular data and interoperability. Direct C bindings are reserved for specialized, performance-critical use cases. This layered approach enables fast, clean, and scalable development of a modern data science language in OCaml.

---

**References:**

* [Owl Numerical Library](https://ocaml.xyz)
* [Apache Arrow](https://arrow.apache.org)
* [GSL Manual](https://www.gnu.org/software/gsl/)
* [LAPACK](https://www.netlib.org/lapack/)
