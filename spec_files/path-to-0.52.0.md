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
- [ ] **Immutable Update Lenses**:
    - [ ] Implement `set()`, `over()`, and `modify()` for deep dict/list updates (e.g. `df |> set($Petal.Length, 1.0)`).
- [ ] **First-class Serializer System**:
    - [ ] Implement `serializer` structure with `writer`/`reader` functions.
    - [ ] Add `^` symbol prefix for serializer identifiers (e.g., `^csv`, `^arrow`).
    - [ ] Implement static coherence checks in the pipeline builder to ensure source/target format matching.

---

## v0.51.3 — Advanced Modeling & Stats 🎯 **INTEROP**

**Objective**: Strengthen the native model evaluator and PMML support beyond linear models.

- [ ] **Advanced PMML Support**:
    - [ ] Native evaluation (no external runtime) for **Decision Trees** and **Random Forests**.
    - [ ] Native evaluation for **XGBoost** and **LightGBM** (standard PMML exports).
- [ ] **Predictive Modeling Refactor**:
    - [ ] Refactor `predict()` to support non-linear model structures.
    - [ ] Implement dummy/one-hot encoding for factor columns in **native `lm()`**.
    - **Expected Syntax**:
      ```t
      clf = read_pmml("forest.pmml")
      df |> mutate($pred = predict(clf, df))
      ```
- [ ] **Model Metrics**:
    - [ ] Expand `glance()` and `tidy()` to return standard statistics for all native model types.

---
 
## v0.51.4 — Plotting Metadata & REPL Viz 🎨 **VISUALIZATION**

**Objective**: Enhance the REPL developer experience for polyglot plotting workloads.

- [ ] **R / ggplot2 Metadata**:
    - [ ] Detect `ggplot` class objects during R evaluation.
    - [ ] Extract plot metadata (title, mapping, layers) instead of raw list structure.
    - [ ] Implement a specialized `pretty_print` for ggplot objects in the REPL.
- [ ] **Python / Matplotlib & Plotly**:
    - [ ] Detect Python plot objects (Figures, plotly dicts).
    - [ ] Extract basic metadata (Labels, data sources).
- [ ] **The `t_show()` helper**:
    - [ ] Implement a `t_show(plot)` utility that saves the plot to a temporary PDF/PNG and prompts the user to open it (or opens it automatically if possible).
    - **Syntax Preview**:
      ```t
      p = rn(command = <{ ggplot(mtcars, aes(wt, mpg)) + geom_point() }>)
      p -- Shows: "ggplot object (Layers: 1, Mapping: wt -> x, mpg -> y)"
      t_show(p) -- Opens the plot in the default system viewer
      ```

---

## v0.52.0 — Julia & Polyglot Pinnacle 🚀 **MILESTONE**

**Objective**: Finalize the **v0.52.0 "Kaméhaméha"** release with full Julia integration and final ecosystem polish.

- [ ] **Julia First-Class Support**:
    - [ ] **Julia Node (`jn()`)**: Specialized pipeline node for Julia scripts.
    - [ ] **Zero-Copy Arrow Interchange**: Shared memory data transfer between Julia and T.

- [ ] **Language Interop Guide**: Expansion with final polyglot examples and deployment strategies.
- [ ] **Final Stabilisation**: Final bug-scrub and execution of the alpha-exit release plan.
