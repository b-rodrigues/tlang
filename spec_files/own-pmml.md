# Feasibility of Owning the PMML R/Python Boundary via JPMML

This note evaluates whether T should provide its **own PMML-facing functions for R and Python**, while standardizing on the **JPMML ecosystem** underneath, so that models can move cleanly into White and back out again without parser mismatches.

## Executive summary

The approach is **feasible and desirable** if the goal is a **"just works" interchange layer** rather than a pure-Python or pure-R implementation.

The cleanest design is:

- **R export/import boundary:** `r2pmml` / JVM-backed JPMML tooling
- **Python scoring/import boundary:** JPMML-backed evaluator tooling
- **T-facing API:** small T-owned wrapper functions that hide the Java details
- **Nix/runtime contract:** always provision a JRE for PMML workflows

This is better than mixing unrelated PMML stacks because it keeps both sides on the same reference implementation family.

## Why this is attractive

The repository already leans in this direction:

- R PMML support is already wired around **`r2pmml`** and a required **`jre`**
- Python PMML support already expects **`pypmml`**, **`sklearn2pmml`**, and **`statsmodels`**
- the flake already provisions **`r2pmml`**, **`pypmml`**, **`sklearn2pmml`**, and **`jpmml-statsmodels`**

So this is not a greenfield idea. It is mostly a question of **standardizing the boundary contract** and making T's API opinionated about which PMML stack is supported.

## Core recommendation

T should expose its own higher-level PMML helpers, but they should be **thin wrappers over JPMML-family tools**, not a new PMML implementation.

That means:

1. **Do not build a custom PMML parser/scorer in R or Python**
2. **Do not rely on mixed parser stacks** when interchange correctness matters
3. **Do standardize on JPMML-compatible artifacts and evaluators**
4. **Do make the JVM requirement explicit and first-class**

## Feasibility by use case

### 1. R model -> PMML -> Python / White

**Feasibility: High**

This is the strongest case.

- `r2pmml` is already the right export path for R
- it is JVM-backed and aligned with the broader JPMML ecosystem
- it avoids the class of compatibility issues caused by weaker downstream PMML readers

If White can consume standards-compliant JPMML-style PMML, this should be the default path.

### 2. Python model -> PMML -> R / White

**Feasibility: Medium to High**

This is also viable, but it depends on the model family:

- **scikit-learn pipelines/models:** strong fit via `sklearn2pmml`
- **statsmodels:** viable via `jpmml-statsmodels`
- **arbitrary Python models:** not universally feasible, because PMML support is model-family dependent

So "own PMML functions for Python" is realistic if the API is explicit that PMML export is supported for **specific model classes**, not for all Python objects.

### 3. White -> PMML -> T / R / Python

**Feasibility: Unknown to Medium**

This depends less on T and more on **what White emits**:

- if White exports standards-compliant PMML that stays within commonly-supported JPMML features, this is promising
- if White emits vendor extensions or partial PMML, compatibility still needs to be tested

So bidirectional interchange is feasible **only if White is part of the compatibility test matrix**.

## Why owning the wrapper layer still makes sense

Even if the implementation is delegated to JPMML tools, T still benefits from owning the API surface:

- T can define one supported PMML workflow instead of several weakly-compatible ones
- T can fail explicitly when a model family is unsupported
- T can hide package/JAR wiring from users
- T can keep the "No Silent Magic" rule intact by rejecting unsupported paths clearly
- T can test White/T round-trips as a product feature

In other words, T should own the **developer experience**, not the PMML engine.

## Proposed product stance

The product stance should be:

> T supports PMML interchange through the JPMML ecosystem. If you want reliable R/Python/White transfer, use the JPMML-backed path. Other PMML stacks are not the compatibility target.

This is a cleaner promise than saying "PMML is supported" while allowing multiple incompatible readers/writers underneath.

## Implementation shape

### R side

Recommended wrapper behavior:

- export via `r2pmml`
- optionally add T-owned validation of the resulting artifact
- keep model-family support explicit in documentation

### Python side

Recommended wrapper behavior:

- prefer a JPMML-backed evaluator path for loading/scoring
- keep `sklearn2pmml` / `jpmml-statsmodels` as the exporter story where applicable
- avoid introducing additional non-JPMML PMML readers as first-class supported paths

If `jpmml-evaluator` is adopted directly, it is a good fit with the stated goal because it keeps scoring on the same implementation family as export.

## Main risks

### 1. JVM dependency becomes mandatory for PMML workflows

This is acceptable, but it must be explicit. PMML in T should be treated like Arrow native support: a real capability with clear runtime requirements.

### 2. Python ecosystem ergonomics

Python users often expect pure-Python tooling. A JVM-backed evaluator is operationally heavier, but it is still the better trade-off if correctness and interoperability matter more than minimal setup.

### 3. White compatibility is still empirical

The strategy reduces compatibility risk, but it does not remove the need for round-trip tests with actual White-produced artifacts.

### 4. Feature coverage is model-family dependent

PMML is not equally strong for every modern model type. T should avoid implying universal support.

## Recommendation

This should move forward.

The recommended direction is:

- **standardize on JPMML-compatible PMML end-to-end**
- **provide T-owned wrapper functions for R and Python**
- **treat White interoperability as an explicit acceptance criterion**
- **document supported model families narrowly and honestly**
- **avoid mixed PMML parser stacks as the primary supported path**

## Suggested acceptance criteria

Before calling the design complete, verify:

1. **R -> PMML -> Python** works on representative linear, tree, and ensemble models
2. **Python -> PMML -> R** works for supported sklearn/statsmodels cases
3. **T/White round-trips** succeed on at least one real artifact in each supported family
4. failures for unsupported models are explicit and descriptive
5. the Nix environment provisions the required Java runtime automatically for PMML workflows

## Final assessment

**Feasibility: High for a JPMML-first wrapper strategy.**

If the objective is reliable interchange with White, the right move is not to invent a new PMML engine. It is to make T's own PMML functions a **thin, explicit, well-tested façade over the JPMML ecosystem** and to declare that stack as the only compatibility target that T promises to support.
