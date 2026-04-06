# Feasibility of PMML-Based R/Python Model Interchange via JPMML

This note recommends that T provide its **own PMML read/write and scoring functions for R and Python**, while standardizing on the **JPMML ecosystem** underneath, so that models can move cleanly between **R and Python** with consistent cross-language behavior.

For brevity, the rest of this note treats this as the **R/Python PMML boundary**.

## Executive summary

The approach is **feasible and desirable** if the goal is not generic "PMML support" but a **single cross-language execution boundary around one semantic engine**, built by reusing as much mature ecosystem tooling as possible while keeping the T-side experience smooth and transparent.

The cleanest design is:

- **R export/import boundary:** `r2pmml` / JVM-backed JPMML tooling
- **Python scoring/import boundary:** JPMML-backed evaluator tooling
- **T-facing API:** small T-owned wrapper functions, ideally exposed as a **custom serializer** pair in the pipeline system (one T-level serializer object that owns the matching PMML writer and reader)
- **Execution authority:** JPMML is the scoring authority whenever PMML is involved
- **Execution model:** PMML workflows run on a JVM-backed scoring runtime
- **Nix/runtime contract:** always provision the JVM-backed PMML runtime for PMML workflows

This is better than mixing unrelated PMML stacks because it keeps both sides on the same semantic engine instead of letting export and scoring drift into different edge-case behavior, transformation handling, or model-evaluation results over time.

## Why this is attractive

The repository already leans in this direction:

- R PMML support is already wired around **`r2pmml`** and a required **`jre`**
- Python PMML support already expects **`pypmml`**, **`sklearn2pmml`**, and **`jpmml-statsmodels`**
- the flake already provisions **`r2pmml`**, **`pypmml`**, **`sklearn2pmml`**, and **`jpmml-statsmodels`**
- **`jpmml-evaluator`** is the natural additional reading/scoring companion if T standardizes on one JVM-based PMML story
- that evaluator should be treated as a planned required addition to the flake rather than an optional extra

So this is not a greenfield idea. It is mostly a question of **standardizing the boundary contract** and making T's API opinionated about which PMML stack is supported.

## Core recommendation

T should expose its own higher-level PMML helpers, but they should be **thin wrappers over JPMML-family tools**, not a new PMML implementation.

The guiding principle should be:

- **reuse existing, proven PMML tooling wherever possible**
- **maximize cross-language compatibility by standardizing on one execution path**
- **make the user experience smooth and transparent without hiding what runtime is actually doing the scoring**
- **avoid pure-Python PMML readers as first-class paths because they reintroduce mixed semantics**

That means:

1. **Do not build a custom PMML parser/scorer in R or Python**
2. **Do not rely on mixed parser stacks** when interchange correctness matters
3. **Do standardize on JPMML-compatible artifacts and evaluators**
4. **Do treat JPMML as the only scoring authority in cross-language PMML mode**
5. **Do make the JVM-backed execution model explicit and first-class**

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

So "own PMML functions for Python" is realistic only if the API is explicit that PMML export is supported for **specific model classes**, not for all Python objects.

### 3. T-owned custom serializer for PMML interchange

**Feasibility: High**

This is a natural fit for the direction described in the existing `spec_files/custom-serializers.md` planning note.

A PMML serializer should be treated as a first-class serializer pair:

- writer side: emit PMML through `r2pmml`, `sklearn2pmml`, or `jpmml-statsmodels`
- reader side: load/score through the canonical JPMML-backed evaluator
- pipeline contract: one serializer identifier, one execution engine, one supported compatibility story

This would make PMML interchange consistent with the broader plan to group readers and writers into a single T-level serializer object rather than scattering separate function references through nodes.

It also gives T a clean place to enforce a stricter artifact contract, for example:

- one deterministic `.pmml` artifact as the canonical payload, for example `<artifact_id>.pmml`
- optional sidecar metadata such as `metadata.json`
- deterministic serializer output suitable for caching and Nix-style reproducibility

## Why owning the wrapper layer still makes sense

Even if the implementation is delegated to JPMML tools, T still benefits from owning the API surface:

- T can define one supported PMML workflow instead of several weakly-compatible ones
- T can fail explicitly when a model family is unsupported
- T can hide package/JAR wiring from users
- T can keep the "No Silent Magic" rule intact by rejecting unsupported paths clearly
- T can make PMML a coherent custom serializer instead of an ad hoc set of helpers
- T can ensure that export and scoring both resolve to the same semantic authority
- T can present a smoother UX while still being transparent about the JVM-backed execution model

In other words, T should own the **developer experience**, not the PMML engine.

## Proposed product stance

The product stance should be:

> T supports PMML as a strict, JVM-backed interchange format using the JPMML ecosystem as the single execution authority. Only models and pipelines that can be faithfully represented and evaluated within this system are supported. Unsupported cases fail explicitly.

This is a cleaner promise than saying "PMML is supported" while allowing multiple incompatible readers/writers underneath. In practice, T should reject unsupported non-JPMML PMML paths explicitly with a descriptive error rather than silently accepting them, consistent with T's **No Silent Magic** rule.

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

`jpmml-evaluator` is the recommended direct Python evaluator because it keeps scoring on the same implementation family as export. It is the clearest candidate for a dedicated JVM-backed Python-side PMML reader/scorer, and it should be added to the flake as part of the supported PMML execution path. It should be treated as a Java-bridged Python integration point rather than as a pure-Python parser.

### Supported surface

The supported model surface should stay intentionally narrow:

- linear and GLM-style models
- tree-based models where the JPMML toolchain already has stable support
- basic sklearn pipelines without arbitrary user-defined transforms
- statsmodels cases that already map cleanly through the JPMML bridge

Everything else should fail fast rather than being "best effort".

### Transformation fidelity

The biggest risk is not the model coefficients; it is preprocessing.

PMML is a strong fit when transformations can be represented by PMML primitives such as scaling, encoding, and straightforward pipeline steps. It is a weak fit when preprocessing depends on arbitrary Python or R logic. T should therefore state explicitly that only pipelines whose transformations can be faithfully expressed in PMML are supported.

### Validation mode

T should add a validation mode for PMML workflows, ideally as a utility such as `compare_pmml_scores(data, model)`.

That mode would:

1. score in the originating runtime
2. score through the JPMML execution path
3. compare outputs and surface any mismatch clearly

This would serve as a debugging tool, a test primitive, and a way to make the serializer contract more trustworthy.

## Main risks

### 1. JVM dependency becomes mandatory for PMML workflows

This is acceptable, but it must be explicit. PMML in T should be treated like Arrow native support: a real capability with clear runtime requirements.

More importantly, users should understand that PMML execution is not "still just Python" or "still just R"; it is a JVM-backed execution mode that those runtimes hand off to.

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
- **treat JPMML as the sole execution authority whenever PMML is active**
- **support only model families and preprocessing steps that can be represented faithfully**
- **document supported model families narrowly and honestly**
- **avoid mixed PMML parser stacks as the primary supported path**

## Suggested acceptance criteria

Before calling the design complete, verify:

1. **R -> PMML -> Python** works on representative linear, tree, and ensemble models
2. **Python -> PMML -> R** works for supported sklearn/statsmodels cases
3. the PMML reader/writer pair is exposed coherently as a serializer contract in T
4. representative R/Python PMML cases are covered by `tests/golden/` or `tests/integration/` in the existing test suites
5. PMML scoring goes through the JPMML execution path rather than mixed scoring engines
6. failures for unsupported models or unsupported preprocessing are explicit and descriptive
7. the Nix environment provisions the required JVM-backed runtime automatically for PMML workflows
8. a validation mode exists to compare native-runtime outputs against JPMML outputs

## Final assessment

**Feasibility: High for a JPMML-first wrapper strategy.**

If the objective is reliable interchange between R and Python, the right move is not to invent a new PMML engine. It is to make T's own PMML functions a **thin, explicit, well-tested facade over the JPMML ecosystem**, surface that facade as the PMML custom serializer that T pipelines use by default, and keep the whole feature narrow enough that one semantic engine remains the authority.
