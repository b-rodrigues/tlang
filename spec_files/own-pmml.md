# Feasibility of Owning the PMML R/Python Boundary via JPMML

This note evaluates whether T should provide its **own PMML read/write and scoring functions for R and Python**, while standardizing on the **JPMML ecosystem** underneath, so that models can move cleanly between **R and Python** without parser mismatches.

## Executive summary

The approach is **feasible and desirable** if the goal is a **"just works" interchange layer** rather than a pure-Python or pure-R implementation.

The cleanest design is:

- **R export/import boundary:** `r2pmml` / JVM-backed JPMML tooling
- **Python scoring/import boundary:** JPMML-backed evaluator tooling
- **T-facing API:** small T-owned wrapper functions, ideally exposed as a **custom serializer** pair in the pipeline system (one T-level object that owns the matching PMML writer and reader)
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

### 1. R model -> PMML -> Python

**Feasibility: High**

This is the strongest case.

- `r2pmml` is already the right export path for R
- it is JVM-backed and aligned with the broader JPMML ecosystem
- it avoids the class of compatibility issues caused by weaker downstream PMML readers

If Python consumes the artifact through the same JPMML family, this should be the default path.

### 2. Python model -> PMML -> R

**Feasibility: Medium to High**

This is also viable, but it depends on the model family:

- **scikit-learn pipelines/models:** strong fit via `sklearn2pmml`
- **statsmodels:** viable via `jpmml-statsmodels`
- **arbitrary Python models:** not universally feasible, because PMML support is model-family dependent

So "own PMML functions for Python" is realistic if the API is explicit that PMML export is supported for **specific model classes**, not for all Python objects.

### 3. T-owned custom serializer for PMML interchange

**Feasibility: High**

This is a natural fit for the direction described in `spec_files/custom-serializers.md`.

A PMML serializer should be treated as a first-class serializer pair:

- writer side: emit PMML through `r2pmml`, `sklearn2pmml`, or `jpmml-statsmodels`
- reader side: load/score through a JPMML-backed Python evaluator
- pipeline contract: one serializer identifier, one supported compatibility story

This would make PMML interchange consistent with the broader plan to group readers and writers into a single T-level serializer object rather than scattering separate function references through nodes.

## Why owning the wrapper layer still makes sense

Even if the implementation is delegated to JPMML tools, T still benefits from owning the API surface:

- T can define one supported PMML workflow instead of several weakly-compatible ones
- T can fail explicitly when a model family is unsupported
- T can hide package/JAR wiring from users
- T can keep the "No Silent Magic" rule intact by rejecting unsupported paths clearly
- T can make PMML a coherent custom serializer instead of an ad hoc set of helpers

In other words, T should own the **developer experience**, not the PMML engine.

## Proposed product stance

The product stance should be:

> T supports PMML interchange through the JPMML ecosystem. If you want reliable R/Python transfer, use the JPMML-backed path. Other PMML stacks are not the compatibility target.

This is a cleaner promise than saying "PMML is supported" while allowing multiple incompatible readers/writers underneath.

## Implementation shape

### R side

Recommended wrapper behavior:

- export via `r2pmml`
- optionally add T-owned validation of the resulting artifact
- keep model-family support explicit in documentation
- expose the pair through a T-owned serializer abstraction rather than a one-off PMML path

### Python side

Recommended wrapper behavior:

- prefer a JPMML-backed evaluator path for loading/scoring
- keep `sklearn2pmml` / `jpmml-statsmodels` as the exporter story where applicable
- avoid introducing additional non-JPMML PMML readers as first-class supported paths
- register the reader/writer combination as the PMML serializer contract used by pipelines

`jpmml-evaluator` is the recommended direct Python evaluator because it keeps scoring on the same implementation family as export.

## Main risks

### 1. JVM dependency becomes mandatory for PMML workflows

This is acceptable, but it must be explicit. PMML in T should be treated like Arrow native support: a real capability with clear runtime requirements.

### 2. Python ecosystem ergonomics

Python users often expect pure-Python tooling. A JVM-backed evaluator is operationally heavier, but it is still the better trade-off if correctness and interoperability matter more than minimal setup.

### 3. Interop still has to be tested across real R/Python flows

The strategy reduces compatibility risk, but it does not remove the need for round-trip tests with actual R-produced and Python-produced artifacts.

### 4. Feature coverage is model-family dependent

PMML is not equally strong for every modern model type. T should avoid implying universal support.

## Recommendation

This should move forward.

The recommended direction is:

- **standardize on JPMML-compatible PMML end-to-end**
- **provide T-owned wrapper functions for R and Python**
- **make PMML a first-class custom serializer/read-write pair**
- **document supported model families narrowly and honestly**
- **avoid mixed PMML parser stacks as the primary supported path**

## Suggested acceptance criteria

Before calling the design complete, verify:

1. **R -> PMML -> Python** works on representative linear, tree, and ensemble models
2. **Python -> PMML -> R** works for supported sklearn/statsmodels cases
3. the PMML reader/writer pair is exposed coherently as a serializer contract in T
4. failures for unsupported models are explicit and descriptive
5. the Nix environment provisions the required Java runtime automatically for PMML workflows

## Final assessment

**Feasibility: High for a JPMML-first wrapper strategy.**

If the objective is reliable interchange between R and Python, the right move is not to invent a new PMML engine. It is to make T's own PMML functions a **thin, explicit, well-tested facade over the JPMML ecosystem**, and ideally surface that facade as the PMML custom serializer that T pipelines use by default.
