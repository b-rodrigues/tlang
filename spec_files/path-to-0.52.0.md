# Phased Roadmap to Version 0.52.0

This document outlines the step-by-step evolution of the T language from the current state (v0.51.0) through several targeted point releases, culmininating in the **v0.52.0 "Kaméhaméha"** milestone.

---

## v0.51.1 — Alpha Hardening & Performance 🎯 **STABILITY**

**Objective**: Complete the "Finish Alpha" checklist and ensure production-grade performance on the Arrow backend.

- [x] **Arrow Backend Optimization**:
    - [x] **Grouped `mutate` / Windowing**: Materialize Arrow window kernels to replace OCaml fallbacks for `dense_rank`, `lag`, etc.
    - [x] **Grouping Kernels**: Optimize hash-based grouping for high-cardinality keys (>10k groups).
- [x] **Large Dataset Benchmarks**:
    - [x] Achieve <1s baseline for core verbs (select/filter/mutate) on 100k rows.
    - [x] Achieve <10s baseline for core verbs on 1M rows.
- [x] **Edge Case Hardening**:
    - [x] Exhaustive tests for empty groups, all-NA groups, and single-row groups.
    - [x] Handle window overflows and tie-breaking in rank functions.
- [x] **Formula Engine**:
    - [x] Support for interaction terms and collinearity detection in `lm()`.

---

## v0.51.2 — Language Maturity 🎯 **ERGONOMICS**

**Objective**: Expand the core syntax to close gaps in functional expressivity and developer experience.

- [x] **Pattern Matching (`match`)**:
    - [x] Implement `match` expression for lists, errors, and NA values.
    - **Expected Syntax**:
      ```t
      msg = match(x) {
        [head, ..tail] => "Starts with {head}",
        []             => "Empty",
        Error { msg }  => "Error: {msg}",
        NA             => "Missing"
      }
      ```
- [x] **Immutable Update Lenses**:
    - [x] Implement `set()`, `over()`, and **variadic `modify()`** for deep surgical updates (e.g., `df |> modify(col1, f1, col2, f2)`).
    - [x] **Variadic `compose()`**: Chain any number of lenses into a single path.
    - [x] **Pipeline Lenses**: `node_lens()` and `env_var_lens()` for orchestration.
- [x] **Lens Library Extensions**:
    - [x] **`idx_lens(i)`**: Target elements in a List or Vector by index.
    - [x] **`filter_lens(p)`**: Target all elements in a collection satisfying a predicate.
    - [x] **Row Lenses**: `row_lens(index)` for targeting specific rows in a DataFrame.
- [x] **First-class Serializer System**:
    - [x] Implement `serializer` structure with `writer`/`reader` functions.
    - [x] Add `^` symbol prefix for serializer identifiers (e.g., `^csv`, `^arrow`).
    - [x] Implement static coherence checks in the pipeline builder to ensure source/target format matching.

---

## v0.51.3 — Advanced Modeling & Stats 🎯 **INTEROP**

**Objective**: Strengthen the native model evaluator and PMML support beyond linear models.

- [x] ONNX support.
- [x] **Advanced PMML Support**:
    - [x] Native evaluation (no external runtime) for **Decision Trees** and **Random Forests**.
    - [x] Native evaluation for **XGBoost** and **LightGBM** (standard PMML exports).
- [x] **Predictive Modeling Refactor**:
    - [x] Refactor `predict()` to support non-linear model structures.
    - [x] Implement dummy/one-hot encoding for factor columns in **native `lm()`**.
    - **Expected Syntax**:
      ```t
      clf = read_pmml("forest.pmml")
      df |> mutate($pred = predict(df, clf))
      ```
- [x] **Model Metrics**:
    - [x] Expand `fit_stats()` and `summary()` to return standard statistics for all native model types.

- [x] **Pipeline Infrastructure & Observability**:
    - [x] **Soft-Fail Semantics**: Captured errors (`VError`) allow pipelines to complete and be inspected.
    - [x] **Diagnostic Propagation**: Automatic accumulation of warnings across the DAG.
    - [x] **Selective Unwrapping**: Transparent interop for artifacts while preserving diagnostic access for introspection.
    - [x] **Enhanced Introspection**: `read_node()`, `read_pipeline()`, and recursive `explain()`.
    - [x] **Suppression combinators**: `suppress_warnings` for acknowledgeable noise.

- [x] **Standardized Missingness & "Death to Null"**:
    - [x] **Unified NA Support**: Complete removal of `null`/`VNull` in favor of typed `NA` values.
    - [x] **Strict NA Enforcement**: Core operators and controls (`if`, `filter`) raise `NAPredicateError` by default.
    - [x] **Consistent API**: Standardized `na_ignore` (transforms) and `na_rm` (aggregations) parameters.

---
 
## v0.51.4 — Plotting Metadata & REPL Viz 🎨 **VISUALIZATION**

**Objective**: Enhance the REPL developer experience for polyglot plotting workloads.

- [x] **R / ggplot2 Metadata**:
    - [x] Detect `ggplot` class objects during R evaluation.
    - [x] Extract plot metadata (title, mapping, layers) instead of raw list structure.
    - [x] Implement a specialized `pretty_print` for ggplot objects in the REPL.
- [x] **Python / Matplotlib & Plotnine**:
    - [x] Detect Python plot objects (Figures, Axes, plotnine ggplot objects).
    - [x] Extract basic metadata (title, labels, mappings, layers).
- [x] **The `show_plot()` helper**:
    - [x] Implement a `show_plot(plot)` utility that saves the plot to `_pipeline/` and opens it with the configured visualization tool when possible.
    - **Syntax Preview**:
      ```t
      p = rn(command = <{ ggplot(mtcars, aes(wt, mpg)) + geom_point() }>)
      p -- Shows: "ggplot object (Layers: 1, Mapping: wt -> x, mpg -> y)"
      show_plot(p) -- Opens the plot with the configured visualization tool
      ```

---

## v0.52.0 — Julia & Polyglot Pinnacle 🚀 **MILESTONE**

**Objective**: Finalize the **v0.52.0 "Kaméhaméha"** release with full Julia integration and final ecosystem polish.

- [ ] **Julia First-Class Support**:
    - [ ] **Julia Node (`jn()`)**: Specialized pipeline node for Julia scripts.
    - [ ] **Zero-Copy Arrow Interchange**: Shared memory data transfer between Julia and T.

- [ ] **Language Interop Guide**: Expansion with final polyglot examples and deployment strategies.
- [ ] **Final Stabilisation**: Final bug-scrub and execution of the alpha-exit release plan.
