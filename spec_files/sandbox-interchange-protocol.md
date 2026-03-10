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

* Wraps exporter (`r2pmml`, `sklearn2pmml`, etc.)
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

Below is the additional RFC section introducing a **phased implementation plan** and explicitly formalizing **user-provided serializers** as first-class citizens.

This integrates cleanly with the previously defined Arrow / PMML / JSON tiered architecture.

---

# RFC Addendum: Phased Implementation Plan and Extensibility

## 1. Design Principle

T must provide:

1. **Sensible, zero-configuration defaults**
2. **A clear migration path toward richer cross-language semantics**
3. **Full user override capability at every stage**

Built-in keywords (`"json"`, `"arrow"`, `"pmml"`) are convenience layers — not restrictions.

Users must always be able to provide:

* Custom serializer functions
* Custom deserializer functions
* Custom metadata handlers

T never removes flexibility in favor of convenience.

---

# 2. Phased Implementation Plan

The serialization system will be implemented incrementally in five phases.

---

## Phase 1 — JSON Baseline (MVP)

### Goal

Enable universal object transport across R, Python, Julia, and T.

### Scope

* Built-in keyword: `"json"`
* T-provided R and Python serializer functions
* Basic scalar, vector, list, dict support
* Optional tagged JSON for structured reconstruction

### Node API

```python
node(
    command = <{ ... }>,
    runtime = R,
    serializer = "json",
    deserializer = "json"
)
```

### Internal Requirements

* Embed `t_write_json` and `t_read_json` into sandbox (R and Python)
* These functions should be defined within pipeline.nix and reused for each derivation
* Deterministic JSON encoding
* Metadata sidecar file (class/type hints)

### Deliverable

Cross-language transport of:

* Scalars
* Lists
* Nested objects
* Small structured configs

This is the foundation.

---

## Phase 2 — Arrow for Tabular Data

### Goal

Efficient, typed DataFrame exchange.

### Scope

* Built-in keyword: `"arrow"`
* R: arrow::write_ipc_stream / read_ipc_stream
* Python: pyarrow
* OCaml: Arrow C data interface bindings

### Node API

```python
node(
    command = <{ raw_data |> summarize(...) }>,
    runtime = R,
    serializer = "arrow",
    deserializer = "arrow"
)
```

### Guarantees

* Zero-copy where possible
* Preserved column types
* No CSV fallback

### Deliverable

Production-grade DataFrame interoperability.

---

## Phase 3 — PMML for Models

### Goal

Language-neutral predictive model exchange with full statistical context (coefficients, standard errors, p-values, and goodness-of-fit statistics).

### Scope

* Built-in keyword: `"pmml"`
* **R backend**: `r2pmml` (preferred for its rich PMML support via JPMML).
* **Python backend**: `sklearn2pmml`.
* **T-native PMML parser**: Recursive XML parser capable of mapping PMML elements to T linear and tree model records.
* **Enrichment layer**: Post-export XML modification in runtimes to inject stats not natively included in standard PMML (e.g., standard errors in `RegressionModel`).

### Node API

```python
model = node(
    command = <{ lm(mpg ~ wt + hp, data = data) }>,
    runtime = R,
    serializer = "pmml"
)
```

### Deliverable

T-native model abstraction capable of:

* `predict(df, model)`: Native execution without runtime overhead.
* `summary(model)`: Full coefficient table with estimates, std. errors, and p-values.
* `fit_stats(model)`: Goodness-of-fit metrics (R², Adj. R², AIC, BIC, etc.).

---

## Principles for Model Bridge Development

To expand T's model support (e.g., GLMs, Random Forests, XGBoost), developers must follow these core principles:

### 1. Statistical Context Preservation
A model in T is not just a scoring function; it is a statistical object. 
*   **Don't stop at coefficients**: Ensure the bridge captures standard errors, t-statistics, and p-values.
*   **Capture Goodness-of-Fit**: Expose R-squared, Adj. R-squared, AIC, BIC, Log-Likelihood, and Deviance.
*   **Consistency**: The T-side `summary(model)` and `fit_stats(model)` must feel as complete as their R/Python counterparts.

### 2. Prefer `r2pmml` and `JPMML` backends
While the base `pmml` package exists in R, `r2pmml` (and the underlying Java JPMML library) is preferred because:
*   It supports a wider range of models (including scikit-learn models via `sklearn2pmml`).
*   It handles feature transformations more robustly.
*   It produces highly standardized XML structure that is easier for T to parse deterministically.

### 3. Context-Aware XML Enrichment
Since standard PMML sometimes omits statistical metadata (like standard errors in a `RegressionModel`), we perform "enrichment" on the R/Python side before the artifact is finalized.
*   **Be Context-Aware**: Use specific XML patterns for substitution (e.g., match `<NumericPredictor name="var"` rather than just `name="var"`) to avoid accidental replacement in `MiningSchema` or other metadata sections.
*   **Standardized Extensions**: Where possible, use standard PMML attributes (like `stdError`, `tStatistic`, `pValue`) or the `<PredictiveModelQuality>` element for model-level stats.

### 4. Strict Symmetry Between Runtime and Parser
The logic used to inject XML attributes in the runtime (R/Python) and the logic used to parse them in T (`pmml_utils.ml`) must be updated in lockstep.
*   Always use `fmt <- function(x) sprintf("%.15g", x)` in R to preserve precision during interchange.
*   Ensure T parser handles both standard attributes and our custom extensions gracefully (returning `VNull` if missing).

---

## Phase 4 — Semantic Object Reconstruction

### Goal

Move from "transport" to "semantic integration".

### Scope

* Mapping PMML → T model objects
* Mapping JSON-tagged objects → typed T structures
* Versioned deserializers
* Class registry inside T

Deliver:

```text
PMML → T::LinearModel
PMML → T::TreeModel
JSON(tag=matrix) → T::Matrix
```

---

# 3. User-Provided Serializers (First-Class Feature)

Built-in keywords are shorthand.

The node API must always support explicit functions:

```python
node(
    command = <{ ... }>,
    runtime = R,
    serializer = "my_custom_writer",
    deserializer = "my_custom_reader",
    functions = "src/my_io.R"
)
```

Or in Python:

```python
node(
    command = <{ ... }>,
    runtime = Python,
    serializer = my_writer,
    deserializer = my_reader,
    functions = "src/io.py"
)
```

---

## 3.1 Formal Rule

Resolution order for `serializer`:

1. If string matches built-in keyword → use built-in
2. If string matches provided function name → use user function
3. If callable object provided → use directly
4. Otherwise → error

Built-in keywords are syntactic sugar for:

```text
"json"  → t_write_json / t_read_json
"arrow" → write_arrow / read_arrow
"pmml"  → t_write_pmml / t_read_pmml
```

---

# 4. Overriding Defaults

Users may:

* Replace JSON implementation
* Provide optimized Arrow writer
* Provide custom PMML post-processing
* Implement domain-specific formats

Example:

```python
node(
    command = <{ heavy_object }>,
    runtime = Python,
    serializer = "pickle_writer",
    deserializer = "pickle_reader",
    functions = "src/pickle_io.py"
)
```

T imposes no restrictions beyond determinism and file-path return contract.

---

# 5. Required Contract for Any Serializer

A serializer must:

1. Accept `(object, path)`
2. Write deterministically to `path`
3. Return nothing (or success flag)

A deserializer must:

1. Accept `path`
2. Return reconstructed object

T handles:

* Store paths
* Metadata
* Version tracking

---

# 6. Architectural Invariant

Built-in serializers are:

* Convenience
* Stable defaults
* Fully replaceable

T remains:

* Format-agnostic
* Extensible
* Runtime-neutral

---

# 7. Final Serialization Stack

```text
Layer 3 — JSON  → Generic objects
Layer 2 — Arrow → Tabular data
Layer 1 — PMML  → Models
--------------------------------
Override layer → User-defined serializers
```

Users can always drop below the stack.

---

# 8. Guiding Philosophy

1. Defaults must cover 90% of use cases.
2. Advanced users must never be boxed in.
3. Serialization is transport, not semantics.
4. T owns semantics after deserialization.
5. Extensibility is a core design guarantee.

---

# 9. Arrow Implementation Details (Phase 2)

Arrow interoperability is implemented using the Feather V2 (IPC) format for file-based interchange between runtimes.

## 9.1 Data Flow

1. **Serialization (Output)**:
   - When a node has `serializer = "arrow"`, its output is written to `$out/artifact` using the Arrow IPC format.
   - For **R**: Uses `arrow::write_ipc_file(as.data.frame(object), path)`.
   - For **Python**: Uses `pyarrow.ipc.new_file` to write the table or DataFrame.
   - For **T**: Uses `Arrow_io.write_ipc` (native-backed tables only).

2. **Deserialization (Input)**:
   - When a node consumes a dependency with `deserializer = "arrow"` (or by default if the upstream used `serializer = "arrow"` and matches), it reads from the upstream's `$out/artifact`.
   - For **R**: Uses `arrow::read_ipc_file(path)`.
   - For **Python**: Uses `pyarrow.ipc.open_file(path).read_pandas()`.
   - For **T**: Uses `Arrow_io.read_ipc`.

## 9.2 Type Mapping

| T Type | Arrow Type | R Type | Python Type |
|--------|------------|--------|-------------|
| Int    | Int64      | integer / double | int64 |
| Float  | Float64    | double | float64 |
| Bool   | Boolean    | logical | bool |
| String | String     | character | object / string |
| NA     | Null       | NA      | None / NaN |

## 9.3 Usage Example

```python
import "iris.csv" as raw_data

# Process in R
iris_summary = node(
    command = <{
        raw_data %>%
          group_by(Species) %>%
          summarize(mean_len = mean(Sepal.Length))
    }>,
    runtime = R,
    serializer = "arrow"
)

# Consume in Python
verified = node(
    command = <{
        print(iris_summary.head())
        return iris_summary.mean_len.mean() > 5
    }>,
    runtime = Python,
    deserializer = "arrow"
)
```

## 9.4 Technical Invariants

- **IPC Format**: T uses the Arrow IPC "File" format (Feather V2), which includes a footer with schema information, rather than the "Stream" format.
- **Native Handles**: In T, Arrow tables can be "native-backed" (pointing directly to C memory managed by Arrow C GLib) or "OCaml-backed". `write_arrow` currently requires a native-backed table.
- **Zero-Copy**: Where supported by the underlying C libraries, deserialization is zero-copy for numeric data.
