# RFC: Model Interchange via PMML for T

## Abstract

This RFC proposes a **cross-language model interchange system** for T using **PMML (Predictive Model Markup Language)**.

* Models are trained in R or Python using standard user APIs.
* T imports models via PMML as an **internal, versioned interchange format**.
* Users never interact with PMML directly.
* T executes models natively, enabling predictions, plotting, and further analysis.

This approach separates **training** from **runtime execution**, ensures **language neutrality**, and avoids embedding foreign runtimes.

---

## Motivation

T aims to:

* Provide **declarative tabular data analysis**
* Execute **models natively**
* Support **reproducibility** and **portability**
* Interoperate with **existing ecosystems** (R, Python, scikit-learn, etc.)

Instead of embedding R or Python runtimes, we use **PMML as a canonical, structured model representation**.

This ensures:

* Stable, language-agnostic IR
* Portable model execution
* Consistent user experience across languages
* Easier versioning and validation

---

## Background: PMML

Predictive Model Markup Language (PMML) is an XML-based standard for predictive model representation.

It supports:

* Regression models (linear, logistic, GLM)
* Tree models (CART, random forests)
* Ensembles, clustering, and more
* Feature transformations and basic preprocessing

### R Ecosystem

* [`pmml`](https://cran.r-project.org/web/packages/pmml/index.html) — exports models to PMML
* [`r2pmml`](https://cran.r-project.org/web/packages/r2pmml/index.html) — alternative exporter with configuration

### Python Ecosystem

* `sklearn2pmml` — sklearn → PMML pipeline exporter
* `nyoka` — export Keras, sklearn, XGBoost models
* `pypmml` — PMML evaluator (Java-backed)

**Important:** Users never use PMML directly. T provides helpers to generate PMML internally from trained models.

---

## Goals

1. Provide **language-agnostic model import** in T
2. Enable **native model execution** in T without embedding runtimes
3. Support common model types (regression, GLM, trees) initially
4. Ensure **user workflows remain natural** (no direct PMML)
5. Enable **future extensions** to other models and pipelines

---

## Architecture Overview

### 1. Training / Export (Python/R)

**R Example:**

```r
library(r2pmml)
library(stats)

fit <- lm(mpg ~ wt + cyl, data = mtcars)

# Export PMML for T
t_export_model(fit, "model.pmml")
```

* `t_export_model()` wraps `r2pmml` or `pmml` internally
* User never interacts with PMML
* PMML saved in a known location or Nix store path

**Python Example:**

```python
from sklearn.linear_model import LinearRegression
from nyoka import skl_to_pmml

model = LinearRegression().fit(X, y)

# Export PMML for T
t_export_model(model, "model.pmml")
```

* `t_export_model()` uses `nyoka` or `sklearn2pmml` internally
* Ensures PMML conforms to T’s supported schema
* Users stay in native Python APIs (scikit-learn, XGBoost, LightGBM)

---

### 2. T Import & Execution

```t
model = load_pmml("model.pmml")

df |> predict(model)
df |> plot(model)
```

Steps:

1. **Parse PMML XML** → internal T IR
2. **Validate schema** and model type
3. **Build native evaluator**
4. Expose prediction API in T

**Internal IR example:**

```ocaml
type regression_model = {
  coefficients: (string * float) list;
  intercept: float;
  link_function: link;
}

type tree_model = {
  nodes: node list;
}

type t_model =
  | Regression of regression_model
  | Tree of tree_model
  | ...
```

---

### 3. Model Execution Semantics

#### Regression Models

For `<RegressionModel>`:

```
ŷ = intercept + Σ (β_i × x_i)
```

* Applies PMML-defined link function for GLMs (logit, probit, log, etc.)
* Evaluates expressions natively in T

#### Tree Models

For `<TreeModel>`:

* Evaluates nested decision rules
* Supports ensembles by aggregating predictions
* Fully vectorized and native

---

## Advantages of PMML

1. **Language neutrality:** R, Python, or other tools can export to PMML
2. **Broader model support:** Regression, GLM, trees, ensembles, clustering
3. **Formal schema:** Validated, versioned, and stable
4. **Runtime independence:** No R/Python required during inference
5. **Clean separation:** Training ↔ Execution boundary

---

## Limitations

* Advanced pipelines (recipes, preprocessing) require PMML representation or must be mirrored in T
* Complex deep learning models may exceed PMML support
* XML parsing requires robust implementation

---

## Security Considerations

* Validate PMML against schema
* Reject unsupported constructs
* PMML is treated as **data**, never executable code

---

## Open Questions

1. Should T allow model updates (incremental learning) on imported PMML?
2. How to version T IR to remain backward-compatible with PMML updates?
3. How to handle feature preprocessing pipelines cleanly in T?

---

## Recommended Initial Scope

* `<RegressionModel>` — Linear, Logistic, GLM
* `<TreeModel>` — Single decision trees, later ensembles
* `<MiningSchema>` — Columns and field metadata
* `<DerivedField>` — Basic transformations

Later expansion:

* Random forests
* Gradient boosting
* Neural networks
* Ensembles (`<MiningModel>`)

---

## User Experience Principle

* Users **never see PMML**.
* Python / R code stays idiomatic:

```python
model = LinearRegression().fit(X, y)
t_export_model(model, "model.pmml")  # Hidden PMML export
```

```r
fit <- lm(mpg ~ wt + cyl, data = mtcars)
t_export_model(fit, "model.pmml")   # Hidden PMML export
```

* T handles parsing, validation, IR creation, and native evaluation
* Users interact with **T-native model APIs only** (`predict`, `plot`, `tidy`)

---

## Conclusion

Using PMML as a hidden interchange format:

* Provides cross-language interoperability
* Avoids embedding foreign runtimes
* Allows native model execution in T
* Aligns with T’s declarative, reproducible, tabular-first philosophy
* Supports multiple ML ecosystems (R, Python, etc.)

This establishes T as a **language-agnostic model runtime** while keeping user workflows natural.


## Review: Model Interchange via PMML

The core proposal is sound. Using PMML as a hidden interchange format with a clean training/execution boundary is a pragmatic and well-reasoned architectural decision. The "users never see PMML" principle is exactly right — exposing PMML directly would introduce unnecessary complexity into user workflows. The phased rollout starting with `<RegressionModel>` and `<TreeModel>` is also appropriately conservative.

That said, several concerns deserve attention before committing to this architecture.

---

### 1. PMML Exporter Fragility

The PMML exporter ecosystem (`sklearn2pmml`, `nyoka`, `r2pmml`) has historically lagged behind upstream library versions. A user training a model with a recent scikit-learn or XGBoost release may encounter silent omissions or outright export failures depending on exporter version. Since T wraps these exporters internally via `t_export_model()`, users will have no visibility into what was dropped. The RFC should specify a pinning and validation strategy for exporter dependencies, and `t_export_model()` should surface warnings when a model includes constructs that cannot be faithfully represented in PMML.

---

### 2. Preprocessing Pipelines Are the Hard Part

The RFC flags preprocessing as a limitation but undersells how critical this is in practice. Real-world models are typically 30% model and 70% preprocessing — scalers, encoders, imputers, interaction terms. If these transformations are not faithfully captured in PMML's `<DerivedField>` and `<TransformationDictionary>`, T's predictions will silently diverge from those produced by the original training environment, with no obvious error to the user.

This is arguably the highest-risk part of the entire proposal, and it deserves its own dedicated RFC before the architecture is finalized. That RFC should define which preprocessing constructs T will support natively, how unsupported transforms are detected and surfaced, and whether there is a validation step that round-trips a sample of predictions from the source environment against T's evaluator to catch discrepancies early.

---

### 3. Ensemble and Tree Coverage Deserves Prototyping First

PMML's `<MiningModel>` schema for random forests and gradient boosting is complex, and exporters vary significantly in how faithfully they represent model-specific behavior — XGBoost's boosting logic in particular does not map cleanly to the PMML spec. The RFC places ensembles in the "later expansion" tier, which is correct, but it would be worth prototyping this before the roadmap is committed to, to avoid discovering late that ensembles require significant parser complexity or produce subtly incorrect results.

---

### 4. Consider ONNX as a Complement for Python-Side ML Models

For the Python ecosystem specifically, ONNX may be a better fit than PMML for tree-based and ensemble models. The `skl2onnx` converter is more actively maintained than its PMML equivalents and has broader coverage of scikit-learn's API surface. A hybrid approach — PMML for statistical models exported from R (GLMs, survival models, etc.) and ONNX for ML models from Python — would leverage the strengths of each format. The tradeoff is that T would need to maintain two parsers and two IR mappings, which adds implementation surface. This is worth evaluating explicitly rather than leaving as an implicit future option.

---

### Summary

The RFC establishes a clean and well-motivated architecture. The recommendations above are not blockers, but the preprocessing pipeline question in particular should be resolved before implementation begins, as it touches correctness in a way that is difficult to retrofit. A round-trip validation mechanism between the source environment and T's evaluator should be considered a first-class requirement rather than a nice-to-have.
