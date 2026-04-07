# Feasibility of PMML-Based R/Python Model Interchange via JPMML

This note recommends that T provide its **own PMML read/write and scoring functions for R and Python**, while standardizing on the **JPMML ecosystem** underneath, so that models can move cleanly between **R and Python** with consistent cross-language behavior.

For brevity, the rest of this note treats this as the **R/Python PMML boundary**.

## Executive summary

The approach is **feasible and desirable** if the goal is not generic "PMML support" but a **single cross-language execution boundary around one semantic engine**, built by reusing as much mature ecosystem tooling as possible while keeping the T-side experience smooth and transparent.

The cleanest design is:

- **R export/import boundary:** `r2pmml` / JVM-backed JPMML tooling
- **Python scoring/import boundary:** JPMML-backed evaluator tooling
- **T-facing API:** small T-owned wrapper functions, ideally exposed as a **custom serializer** pair in the pipeline system (one T-level serializer object that owns the matching PMML writer and reader)
- **T's `predict()` implementation:** a JVM bridge to `jpmml-evaluator`, making JPMML the sole scoring authority for all PMML artifacts regardless of origin language
- **Execution authority:** JPMML is the scoring authority whenever PMML is involved
- **Execution model:** PMML workflows run on a JVM-backed scoring runtime
- **Nix/runtime contract:** always provision the JVM-backed PMML runtime for PMML workflows

This is better than mixing unrelated PMML stacks because it keeps both sides on the same semantic engine instead of letting export and scoring drift into different edge-case behavior, transformation handling, or model-evaluation results over time.

A concrete illustration of why mixed stacks fail: `pmml4s` (the Scala backend used by `pypmml`) throws a hard `scala.MatchError` when it encounters a `<PredictiveModelQuality>` element inside `<ModelExplanation>`. This element is valid PMML 4.x and is routinely emitted by R's `pmml` package to carry fit statistics. `pmml4s` simply has no `case` branch for it. This is the class of silent incompatibility that a JPMML-only stance prevents.

## Why this is attractive

The repository already leans in this direction:

- R PMML support is already wired around **`r2pmml`** and a required **`jre`**
- Python PMML support already uses `sklearn2pmml` and `jpmml-statsmodels` (with `pypmml` removed in favor of JPMML Evaluator)
- the flake already provisions **`r2pmml`**, **`sklearn2pmml`**, and **`jpmml-statsmodels`**
- **`jpmml-evaluator`** is the natural additional reading/scoring companion if T standardizes on one JVM-based PMML story
- that evaluator should be treated as a planned required addition to the flake rather than an optional extra

So this is not a greenfield idea. It is mostly a question of **standardizing the boundary contract** and making T's API opinionated about which PMML stack is supported.

## Minimal flake surface

The complete set of dependencies required for the JPMML-backed PMML story is intentionally small:

- **`r2pmml`** (R package) — bundles the `jpmml-r` JAR internally; no separate JAR needed
- **`sklearn2pmml`** (Python package) — bundles the `jpmml-sklearn` and `jpmml-xgboost` JARs internally; no separate JARs needed
- **`jpmml-statsmodels`** (executable JAR, fetched directly from GitHub releases) — no Python or R wrapper exists; used as a CLI converter
- **`jpmml-evaluator`** (library JAR, fetched directly from GitHub releases) — used by T's `predict()` JVM bridge
- **`jre`** in `buildInputs` — required by all of the above

```nix
jpmml-statsmodels = pkgs.fetchurl {
  url = "https://github.com/jpmml/jpmml-statsmodels/releases/download/.../jpmml-statsmodels-executable-*.jar";
  hash = "sha256-...";
};

jpmml-evaluator = pkgs.fetchurl {
  url = "https://github.com/jpmml/jpmml-evaluator/releases/download/.../jpmml-evaluator-*.jar";
  hash = "sha256-...";
};
```

Everything else in the JPMML repository ecosystem (jpmml-spark, jpmml-h2o, jpmml-lightgbm, jpmml-model, jpmml-converter, etc.) is either an internal dependency bundled by the above, or out of scope for T's supported surface.

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

## T's `predict()` architecture

T's `predict()` builtin is a JVM bridge to `jpmml-evaluator`. It takes a PMML artifact path and an input dataset, spawns a JVM process with the evaluator JAR, and returns predictions as a standard T data type. The origin language — R, sklearn, statsmodels — is invisible to anything downstream of the PMML artifact.

This means the T pipeline story is:

```
model_r    :: RModel  → Pmml
model_py   :: PyModel → Pmml
predict    :: Pmml → Data → Predictions
```

Where `Pmml` is T's artifact type for a PMML file. This is a clean abstraction boundary: T owns the developer experience, JPMML owns the evaluation semantics.

## Feasibility by use case

### 1. R model → PMML → Python

**Feasibility: High**

This is the strongest case.

- `r2pmml` is already the right export path for R
- it is JVM-backed and aligned with the broader JPMML ecosystem
- it avoids the class of compatibility issues caused by weaker downstream PMML readers (see the `PredictiveModelQuality` example above)

If Python consumes the artifact through the same JPMML family, this should be the default path.

### 2. Python model → PMML → R

**Feasibility: Medium to High**

This is also viable, but it depends on the model family:

- **scikit-learn pipelines/models:** strong fit via `sklearn2pmml`, which also bundles XGBoost support for models embedded in sklearn pipelines
- **statsmodels:** viable via `jpmml-statsmodels`
- **arbitrary Python models:** not universally feasible, because PMML support is model-family dependent

So "own PMML functions for Python" is realistic only if the API is explicit that PMML export is supported for **specific model classes**, not for all Python objects.

### 3. statsmodels → PMML → R (inferential statistics)

**Feasibility: Medium**

PMML is not only useful for scoring. A statsmodels model exported via `jpmml-statsmodels` can carry fit statistics through `<ModelExplanation><PredictiveModelQuality>` (R², AIC, BIC, F-statistic, log-likelihood) and coefficient values through `<RegressionTable>`. These can be consumed in R by parsing the PMML artifact as XML:

```r
library(xml2)

doc <- read_xml("model.pmml")

# fit statistics
quality <- xml_find_first(doc, "//PredictiveModelQuality")
xml_attr(quality, "r2")
xml_attr(quality, "aic")
xml_attr(quality, "fPValue")

# coefficients
coefs <- xml_find_all(doc, "//NumericPredictor")
xml_attr(coefs, "coefficient")
```

This is a legitimate cross-language data flow beyond scoring — passing inferential output from a Python estimation step into an R reporting or post-processing step. T should document this as a supported pattern.

The limitation is that per-coefficient p-values are not a standard PMML attribute, so their availability depends on what `jpmml-statsmodels` actually emits. If per-coefficient inference is critical, a JSON sidecar alongside the PMML artifact is a more reliable path.

### 4. T-owned custom serializer for PMML interchange

**Feasibility: High**

This is a natural fit for the direction described in the existing `spec_files/custom-serializers.md` planning note.

A PMML serializer should be treated as a first-class serializer pair:

- writer side: emit PMML through `r2pmml`, `sklearn2pmml`, or `jpmml-statsmodels`
- reader side: load/score through the canonical JPMML-backed evaluator
- pipeline contract: one serializer identifier, one execution engine, one supported compatibility story

This would make PMML interchange consistent with the broader plan to group readers and writers into a single T-level serializer object rather than scattering separate function references through nodes.

It also gives T a clean place to enforce a stricter artifact contract:

- one deterministic `.pmml` artifact as the canonical payload
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

`jpmml-evaluator` is the recommended direct Python evaluator because it keeps scoring on the same implementation family as export. It should be treated as a Java-bridged Python integration point rather than as a pure-Python parser.

### Supported surface

The supported model surface should stay intentionally narrow:

- linear and GLM-style models
- tree-based models where the JPMML toolchain already has stable support
- basic sklearn pipelines without arbitrary user-defined transforms
- XGBoost models embedded in sklearn pipelines (covered by `sklearn2pmml`'s bundled `jpmml-xgboost`)
- statsmodels cases that already map cleanly through the JPMML bridge

Everything else should fail fast rather than being "best effort".

### Transformation fidelity

The biggest risk is not the model coefficients; it is preprocessing.

PMML is a strong fit when transformations can be represented by PMML primitives such as scaling, encoding, and straightforward pipeline steps. It is a weak fit when preprocessing depends on arbitrary Python or R logic. T should therefore state explicitly that only pipelines whose transformations can be faithfully expressed in PMML are supported.

### Validation mode

T should add a validation mode for PMML workflows, ideally as a utility such as `compare_native_vs_pmml_scores(data, model)`.

That mode would:

1. score in the originating runtime
2. score through the JPMML execution path
3. compare outputs and surface any mismatch clearly

This would serve as a debugging tool, a test primitive, and a way to make the serializer contract more trustworthy.

## Main risks

### 1. JVM dependency becomes mandatory for PMML workflows

This is acceptable, but it must be explicit. PMML in T should be treated like Arrow native support: a real capability with clear runtime requirements.

Users should understand that PMML execution is not "still just Python" or "still just R"; it is a JVM-backed execution mode that those runtimes hand off to. T's `predict()` makes this handoff explicit by design.

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
- **implement T's `predict()` as a JVM bridge to `jpmml-evaluator`**
- **treat JPMML as the sole execution authority whenever PMML is active**
- **support only model families and preprocessing steps that can be represented faithfully**
- **document supported model families narrowly and honestly**
- **avoid mixed PMML parser stacks as the primary supported path**
- **provision exactly two R/Python packages and two JARs in the flake; nothing more**

## Suggested acceptance criteria

Before calling the design complete, verify:

1. **R → PMML → Python** works on representative linear, tree, and ensemble models
2. **Python → PMML → R** works for supported sklearn/statsmodels cases
3. **statsmodels → PMML → R** fit statistics flow works for the inferential statistics use case
4. the PMML reader/writer pair is exposed coherently as a serializer contract in T
5. representative R/Python PMML cases are covered by `tests/golden/` or `tests/integration/` in the existing test suites
6. PMML scoring goes through the JPMML execution path rather than mixed scoring engines
7. failures for unsupported models or unsupported preprocessing are explicit and descriptive
8. the Nix environment provisions the required JVM-backed runtime automatically for PMML workflows — specifically `r2pmml`, `sklearn2pmml`, the `jpmml-statsmodels` JAR, the `jpmml-evaluator` JAR, and `jre`
9. a validation mode exists to compare native-runtime outputs against JPMML outputs

## Final assessment

**Feasibility: High for a JPMML-first wrapper strategy.**

If the objective is reliable interchange between R and Python, the right move is not to invent a new PMML engine. It is to make T's own PMML functions a **thin, explicit, well-tested facade over the JPMML ecosystem**, surface that facade as the PMML custom serializer that T pipelines use by default, and keep the whole feature narrow enough that one semantic engine remains the authority.

## Appendix: T-Lang API and Runtime Detail

### Proposed Pipeline Syntax

T should expose PMML through its existing custom serializer system. This ensures that the use of PMML as an interchange format is explicit in the pipeline definition.

```t
p = pipeline {
  # Node 1: Estimation in R
  node "estimate_r" {
    package: "r"
    input: train_data
    output: model_r ^pmml  # Declares PMML as the serialization format
    code: "model_r = t_write_pmml(ols(mpg ~ cyl, data=train_data))"
  }

  # Node 2: Scoring in Python (leveraging the exact same JPMML engine)
  node "score_py" {
    package: "python"
    input: model_r ^pmml, test_data
    output: pred_py
    code: "pred_py = t_predict(model_r, test_data)"
  }
}
```

### Standard Library Wrapper Definition (Stubs)

#### `stdlib/pmml.t`

The T standard library will provide these thin wrappers.

**R wrappers (`t_write_pmml`):**
*   Invokes `jpmml::r2pmml()` internally.
*   Handles the conversion of the R model object to a temporary file path that T's serializer can then move to the artifact store.

**Python wrappers (`t_predict`):**
*   Spawns a JVM process: `java -jar ${JPMML_EVALUATOR_JAR} --model ${model_path} --input ${data_csv} --output ${output_csv}`.
*   T's runtime handles the orchestration of these temporary files and the conversion of the output CSV back into an Arrow/Pandas object for the Python node.

### Data Interchange Mechanism

To keep the bridge simple and avoid complex memory mapping between OCaml (T's runtime), Python/R, and the JVM, T will use **CSV as the bridge format for the JPMML CLI tools**:

1.  **T Runtime** serializes the input data to a temporary CSV.
2.  **T Runtime** invokes the JPMML JAR.
3.  **JPMML** writes predictions to a temporary CSV.
4.  **T Runtime** deserializes the predictions and provides them to the node.

While this incurs a small I/O cost, it is perfectly aligned with PMML's typical use case (batch scoring and medium-latency interchange) and ensures maximum reliability across all JPMML-supported platforms.

### Nix Integration and Reproducibility

The JPMML-based strategy is uniquely suited for Nix-backed reproducibility because:

1.  **Fixed-Output Dependencies**: By packaging the JPMML evaluators with `maven.buildMavenPackage`, T identifies the exact version of the scoring logic used. A change in the evaluator's dependency tree or source results in a different Nix store path, preventing silent drift in scoring results over time.
2.  **Minimal Closure**: The use of `jre_headless` ensures that the runtime environment is lean. Only the essential bytecode and a headless JVM are present in the scoring environment.
3.  **Binary Wrappers**: The `makeBinaryWrapper` approach ensures that environmental variables (like `JAVA_HOME`) are correctly scoped to the specific JPMML tool being used, preventing conflicts with other Java-based tools in the system.

This means that a T binary produced today will execute the exact same scoring logic ten years from now, provided the `.pmml` artifact and the Nix store paths are preserved.

## Phased Implementation Plan

To move from the current "mixed authority" implementation to the JPMML-standardized model, the following phases are recommended:

### Phase 1: Bridge Standardization (Current Week)

- **Switch to CSV Bridge**: Refactor `T_score_pmml.score_pmml_jpmml` to use CSV instead of Arrow IPC for input/output between the T runtime and the JPMML executable. This fulfills the "Minimal Flake Surface" requirement by ensuring compatibility with standard JPMML distributions.
- **Environment Handshake**: Hard-code the lookup for `jpmml-evaluator` and `jpmml-statsmodels` in the T compiler's Nix emission logic, ensuring they are always available when a node declares a PMML input.

### Phase 2: Deprecating Native OCaml Scorers

- **Authority Pivot**: Modify `src/packages/stats/predict.ml` to always route through the JPMML bridge if the model artifact is tagged with `^pmml`. 
- **Native Scorer Relocation**: Move the current OCaml Tree/Forest/Linear scoring logic into a dedicated validation module used strictly by `compare_native_vs_pmml_scores`.

### Phase 3: Serializer Lifecycle Completion

- **Implement `t_write_pmml` (R/Python)**: Create the thin wrappers in the T standard library for `r2pmml` and `sklearn2pmml`.
- **Register PMML Serializer**: Formally register the PMML custom serializer in `serialization_registry.ml` with its corresponding reader/writer pairs for all supported target languages.

### Phase 4: Validation and Guardrails

- **Explicit Failure Modes**: Add guards to detect unsupported PMML features (e.g., non-JPMML transformations) early in the pipeline evaluation phase.
- **E2E Golden Tests**: Add a suite of `r -> pmml -> py` and `py -> pmml -> r` tests to the `t_demos` repository, verified against the JPMML execution authority.