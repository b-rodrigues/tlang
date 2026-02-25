Below is your RFC, **extended to include standardized data interchange via Apache Arrow**, and updated to reflect the node-based runtime abstraction (with `"arrow"` and `"pmml"` as built-in serializers).

I’ve kept the structure intact and added a new section after the Architecture Overview to integrate Arrow cleanly and consistently.

---

# RFC: Model Interchange via PMML for T

## Abstract

This RFC proposes a **cross-language model interchange system** for T using **PMML (Predictive Model Markup Language)**, and standardizes **data interchange via Apache Arrow**.

* Models are trained in R or Python using standard user APIs.
* T imports models via PMML as an **internal, versioned interchange format**.
* Tabular data is exchanged via Apache Arrow.
* Users never interact with PMML or Arrow directly.
* T executes models natively, enabling predictions, plotting, and further analysis.

This approach separates:

* **Training** from **runtime execution**
* **Data interchange** from **model interchange**
* **External runtimes** from **T’s native execution engine**

It ensures language neutrality and avoids embedding foreign runtimes.

---

## Motivation

T aims to:

* Provide **declarative tabular data analysis**
* Execute **models natively**
* Support **reproducibility** and **portability**
* Interoperate with **existing ecosystems** (R, Python, scikit-learn, etc.)

Instead of embedding R or Python runtimes, we use:

* **PMML** as a canonical model representation
* **Apache Arrow** as a canonical data representation

This ensures:

* Stable, language-agnostic IR
* Portable model execution
* Efficient, typed data interchange
* Clear separation of concerns
* Easier validation and versioning

---

# Data Interchange: Apache Arrow

## Background

Apache Arrow is a cross-language columnar memory format designed for high-performance data interchange.

It is supported in:

* R (`arrow` package)
* Python (`pyarrow`)
* Many other ecosystems

Arrow provides:

* Schema preservation
* Strong typing
* Efficient columnar layout
* Streaming support
* Zero-copy compatibility (future extension)

---

## Motivation for Arrow

Current node definition:

```python
summary_r = node(
    command = <{ raw_data |> dplyr::group_by(cyl) |> dplyr::summarize(avg_mpg = mean(mpg)) }>,
    runtime = R,
    deserializer = r_read_csv,
    serializer = r_write_csv,
    functions = "src/iolib.R"
)
```

Problems:

* CSV loses type information
* Manual serializer/deserializer functions
* Fragile and repetitive glue code
* Harder to validate schemas

---

## Proposed Standard Serializer Keywords

Replace custom functions with standardized format keywords:

```python
summary_r = node(
    command = <{ raw_data |> dplyr::group_by(cyl) |> dplyr::summarize(avg_mpg = mean(mpg)) }>,
    runtime = R,
    serializer = "arrow",
    deserializer = "arrow"
)
```

### Semantics

If `"arrow"` is specified:

1. T serializes input dataframe to Arrow IPC.
2. External runtime reads Arrow.
3. Runtime writes Arrow output.
4. T deserializes Arrow back to native dataframe.

No user-defined IO code required.

---

## Execution Flow (Data Plane)

```
T dataframe
    ↓
Arrow IPC
    ↓
R / Python runtime
    ↓
Arrow IPC
    ↓
T dataframe
```

Arrow becomes the standardized **data plane**.

---

# Model Interchange: PMML

## Background: PMML

Predictive Model Markup Language is an XML-based standard for predictive model representation.

It supports:

* Regression models (linear, logistic, GLM)
* Tree models (CART, random forests)
* Ensembles, clustering
* Feature transformations and derived fields

---

## R Ecosystem

* [`pmml`](https://cran.r-project.org/web/packages/pmml/index.html)
* [`r2pmml`](https://cran.r-project.org/web/packages/r2pmml/index.html)

---

## Python Ecosystem

* `sklearn2pmml`
* `nyoka`
* `pypmml`

**Important:** Users never manipulate PMML directly.
T provides `t_export_model()` helpers that wrap exporters internally.

---

# Architecture Overview

## 1. Training / Export (Python/R)

### R Example

```r
library(r2pmml)
fit <- lm(mpg ~ wt + cyl, data = mtcars)

t_export_model(fit, "model.pmml")
```

### Python Example

```python
from sklearn.linear_model import LinearRegression

model = LinearRegression().fit(X, y)
t_export_model(model, "model.pmml")
```

`t_export_model()`:

* Wraps exporter (`r2pmml`, `nyoka`, etc.)
* Validates supported constructs
* Pins compatible exporter versions
* Emits warnings if unsupported elements exist

Users never touch PMML.

---

## 2. Node-Level Model Serialization

Model-producing nodes may specify:

```python
model_train = node(
    command = <{ lm(mpg ~ wt + cyl, data = raw_data) }>,
    runtime = R,
    serializer = "pmml"
)
```

or

```python
model_train = node(
    command = <{ LinearRegression().fit(X, y) }>,
    runtime = Python,
    serializer = "pmml"
)
```

If `"pmml"` is specified:

* Runtime exports model to PMML
* T imports PMML
* T converts to internal IR
* T executes natively

PMML becomes the standardized **model plane**.

---

## 3. T Import & Execution

```t
model = load_pmml("model.pmml")

df |> predict(model)
df |> plot(model)
```

Steps:

1. Parse PMML XML
2. Validate schema + version
3. Convert to T IR
4. Compile evaluator
5. Execute natively

---

## Internal IR Example

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

# Unified Interoperability Design

| Plane  | Standard     | Purpose                     |
| ------ | ------------ | --------------------------- |
| Data   | Apache Arrow | Typed tabular interchange   |
| Models | PMML         | Model structure interchange |

External runtimes become transformation engines.
T becomes orchestration + execution engine.

---

# Model Execution Semantics

## Regression

```
ŷ = intercept + Σ (β_i × x_i)
```

Link functions applied per PMML spec.

## Trees

* Nested rule evaluation
* Ensemble aggregation
* Fully vectorized in T

---

# Validation Strategy

To address exporter fragility and preprocessing risks:

1. `t_export_model()` must:

   * Pin exporter versions
   * Emit explicit warnings for dropped constructs
   * Validate schema

2. Optional round-trip validation:

   * Sample predictions in source runtime
   * Compare against T evaluator
   * Fail if tolerance exceeded

This guards against silent divergence.

---

# Advantages

1. Language neutrality
2. Standardized data and model planes
3. No embedded runtimes
4. Strong schema validation
5. Reduced glue code
6. Cleaner node abstraction

---

# Limitations

* Complex preprocessing pipelines require careful support
* PMML exporter ecosystems may lag upstream libraries
* XML parsing complexity
* Advanced ensemble coverage requires phased rollout

---

# Security Considerations

* Arrow schema validation
* Strict PMML schema validation
* No execution of arbitrary code
* Reject unsupported constructs explicitly

---

# Recommended Initial Scope

## Data

* Arrow IPC file-based exchange

## Models

* `<RegressionModel>`
* `<TreeModel>`
* `<MiningSchema>`
* `<DerivedField>` (basic transforms)

Future:

* `<MiningModel>` (ensembles)
* Random forests
* Gradient boosting
* Advanced preprocessing

---

# User Experience Principle

Users interact only with native APIs:

```python
model = LinearRegression().fit(X, y)
t_export_model(model, "model.pmml")
```

```r
fit <- lm(mpg ~ wt + cyl, data = mtcars)
t_export_model(fit, "model.pmml")
```

```python
summary_r = node(
    command = <{ raw_data |> dplyr::summarize(avg = mean(x)) }>,
    runtime = R,
    serializer = "arrow",
    deserializer = "arrow"
)
```

Users never manipulate:

* PMML
* Arrow IPC
* Custom IO glue

T handles:

* Serialization
* Validation
* IR conversion
* Native execution

---

# Conclusion

This RFC establishes:

* **PMML** as the canonical model interchange format
* **Apache Arrow** as the canonical data interchange format
* Standardized serializer keywords (`"arrow"`, `"pmml"`)
* A strict boundary between training and execution
* A clean, extensible runtime abstraction

This architecture positions T as:

* A language-neutral analytics orchestrator
* A high-performance tabular engine
* A native model scoring runtime
* A reproducible and principled system

# RFC Addendum: Serialization of Primitive and Generic Objects

## 1. Motivation

While tabular data and statistical models represent high-value structured objects, T must also support serialization of:

* Scalars (integers, floats, booleans, strings)
* Arrays / vectors
* Lists / dictionaries / named structures
* Nested composite objects
* Lightweight configuration-like objects
* Small intermediate computational results

These objects must:

* Be portable across R, Python, Julia, and T
* Require no user-written serialization code
* Be deterministic and reproducible
* Be human-inspectable when reasonable
* Avoid unnecessary binary complexity

For these object classes, JSON is the appropriate default.

---

## 2. Serialization Strategy Overview

| Object Type                 | Format              | Rationale                                        |
| --------------------------- | ------------------- | ------------------------------------------------ |
| Tabular data                | Arrow IPC / Parquet | Columnar, zero-copy, cross-language              |
| Statistical models          | PMML                | Language-neutral predictive model representation |
| Primitive & generic objects | JSON                | Universally supported, simple, portable          |

JSON becomes the **default fallback format** for non-tabular, non-model objects.

---

## 3. Design: JSON as the Generic Object Transport

### 3.1 Principles

1. Users never manually serialize.
2. R/Python sandbox contains built-in T-provided serializers.
3. T inspects metadata to determine how to deserialize.
4. JSON must be structurally annotated when needed.

---

## 4. Built-in JSON Serializers

### 4.1 R Runtime

T provides:

```r
t_write_json <- function(object, path) {
  jsonlite::write_json(object, path, auto_unbox = TRUE, null = "null")
}

t_read_json <- function(path) {
  jsonlite::read_json(path, simplifyVector = TRUE)
}
```

Uses:

* `jsonlite::toJSON`
* `jsonlite::fromJSON`

No user code required.

---

### 4.2 Python Runtime

T provides:

```python
import json

def t_write_json(obj, path):
    with open(path, "w") as f:
        json.dump(obj, f)

def t_read_json(path):
    with open(path) as f:
        return json.load(f)
```

For numpy support:

```python
import numpy as np

class TEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, np.ndarray):
            return {
                "__type__": "ndarray",
                "dtype": str(obj.dtype),
                "shape": obj.shape,
                "data": obj.tolist()
            }
        return super().default(obj)
```

---

## 5. Supported Object Classes

### 5.1 Scalars

| R         | Python | T      |
| --------- | ------ | ------ |
| numeric   | float  | Float  |
| integer   | int    | Int    |
| logical   | bool   | Bool   |
| character | str    | String |

JSON mapping is direct.

---

### 5.2 Vectors / Arrays

R numeric vector:

```r
c(1, 2, 3)
```

Serialized as:

```json
[1, 2, 3]
```

Python list:

```python
[1, 2, 3]
```

Same JSON representation.

T interprets as:

```
Vector<Float>
```

---

### 5.3 Named Lists / Dictionaries

R:

```r
list(alpha = 0.1, beta = 2)
```

JSON:

```json
{
  "alpha": 0.1,
  "beta": 2
}
```

T interprets as:

```
Map<String, Any>
```

---

### 5.4 Nested Objects

JSON naturally supports nested structures:

```json
{
  "model_config": {
    "alpha": 0.1,
    "penalty": "l2"
  },
  "metrics": [0.8, 0.9, 0.85]
}
```

T recursively reconstructs typed structures.

---

## 6. Type Metadata and Tagged JSON

For richer reconstruction, JSON may include metadata:

```json
{
  "__t_class__": "vector_float",
  "data": [1.0, 2.0, 3.0]
}
```

Or:

```json
{
  "__t_class__": "matrix",
  "nrow": 2,
  "ncol": 2,
  "data": [1,2,3,4]
}
```

This allows:

* Preserving shape
* Avoiding ambiguous reconstruction
* Rebuilding typed T-native objects

---

## 7. Node-Level Usage

### 7.1 Default JSON

```python
config = node(
    command = <{ {"alpha": 0.1, "beta": 2} }>,
    runtime = Python,
    serializer = "json",
    deserializer = "json"
)
```

### 7.2 R Example

```r
params = node(
    command = <{ list(alpha = 0.1, beta = 2) }>,
    runtime = R,
    serializer = "json",
    deserializer = "json"
)
```

T automatically:

1. Executes sandbox
2. Calls built-in `t_write_json`
3. Reads JSON
4. Reconstructs T structure

---

## 8. Why JSON for Generic Objects?

### 8.1 Cross-language universality

* R: jsonlite
* Python: json
* Julia: JSON3
* OCaml (T): Yojson or similar

### 8.2 Deterministic

### 8.3 Human-readable

### 8.4 Simple to debug

### 8.5 Minimal dependency footprint

---

## 9. When JSON Is Not Appropriate

JSON should NOT be used for:

* Large tabular data → use Arrow
* Numerical tensors (large) → consider Arrow or binary format
* Statistical models → use PMML
* Language-specific object graphs → avoid entirely

---

## 10. Complete Serialization Matrix

| Type             | Format    | User API |
| ---------------- | --------- | -------- |
| DataFrame        | `"arrow"` | Built-in |
| Model            | `"pmml"`  | Built-in |
| Scalar           | `"json"`  | Built-in |
| Vector           | `"json"`  | Built-in |
| List / dict      | `"json"`  | Built-in |
| Nested structure | `"json"`  | Built-in |

---

## 11. Architectural Summary

T’s serialization stack becomes:

```
Tier 1: PMML  → Predictive models
Tier 2: Arrow → Tabular data
Tier 3: JSON  → Everything else
```

Each runtime exposes:

```
serializer = "arrow" | "pmml" | "json"
deserializer = same
```

Users never write serialization code.

---

## 12. Design Philosophy

This approach achieves:

* Reproducibility (Nix-store artifacts)
* Language neutrality
* Deterministic pipelines
* Extensibility
* Minimal user burden
* Clear semantic contracts

Most importantly:

T remains the semantic authority.

External runtimes compute.
T owns the meaning.
