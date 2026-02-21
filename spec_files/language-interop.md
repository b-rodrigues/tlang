# T Interop Implementation Guide

## R, Python, Julia → T (Serialized Boundary Model)

---

# 1. Architectural Principles

## 1.1 Canonical Ownership

T owns the canonical data model:

* `DataFrame` → Arrow-backed
* `Vector` → Arrow / native buffer
* `Scalar`
* `List`
* `Dict`
* Typed semantic objects (e.g., `LinearModel`)
* `Foreign<T>` (opaque)

Foreign runtimes are not authoritative for semantics inside T.

---

## 1.2 Serialization Boundary Model

Since foreign runtimes are sandboxed:

```
R / Python / Julia
    ↓
Language-specific serializer
    ↓
Transport
    ↓
Deserializer in T
    ↓
Conversion → Canonical T types
```

There are exactly two allowed transport formats:

| Object class          | Format    |
| --------------------- | --------- |
| Tabular data          | Arrow IPC |
| Structured projection | JSON      |

Binary language-native serialization (pickle, R serialize, Julia Serialization) is **forbidden**.

---

# 2. Tabular Data (Highest Priority)

## 2.1 Canonical Standard

Use:

Apache Arrow

Specifically:

* Arrow IPC Stream format
* Arrow C Data Interface (optional later optimization)

---

## 2.2 R Data Frames

From R

### Required in sandbox:

* `arrow::write_ipc_stream()`

### Export contract:

```r
export_dataframe <- function(df) {
  arrow::write_ipc_stream(df, sink)
}
```

### In T:

1. Receive IPC stream
2. Load into Arrow memory
3. Wrap in `T.DataFrame`

No JSON involved.

---

## 2.3 Python Pandas DataFrames

From Python
Using pandas

### Required:

* `pyarrow`

```python
def export_dataframe(df):
    import pyarrow as pa
    import pyarrow.ipc as ipc
    table = pa.Table.from_pandas(df)
    sink = pa.BufferOutputStream()
    writer = ipc.new_stream(sink, table.schema)
    writer.write_table(table)
    writer.close()
    return sink.getvalue()
```

T loads as Arrow → `T.DataFrame`.

---

## 2.4 Julia DataFrames

From Julia
Using DataFrames.jl
and Arrow.jl.

```julia
Arrow.write(io, df)
```

Same ingestion path in T.

---

## 2.5 Schema Rules

T must enforce:

* Stable column order
* Explicit nullability
* Stable type mapping:

  * int → Int64
  * float → Float64
  * string → UTF8
  * categorical → dictionary encoding

No implicit widening.

---

# 3. Linear Regression Models (Second Priority)

These are **semantic projections**, not structural conversions.

We define a canonical T type:

```t
type LinearModel {
  coefficients: Vector<Float64>
  intercept: Float64
  fitted: Vector<Float64>?
  residuals: Vector<Float64>?
  r_squared: Float64?
  sigma: Float64?
  metadata: Dict
}
```

No runtime environments.
No callable closures.
No foreign pointers.

---

# 4. R lm → T.LinearModel

## Source: R `lm`

Sandbox must implement:

```r
export_lm <- function(model) {
  summary_model <- summary(model)

  list(
    __type__ = "R.lm",
    coefficients = as.numeric(coef(model)),
    intercept = as.numeric(coef(model)[1]),
    fitted = as.numeric(fitted(model)),
    residuals = as.numeric(residuals(model)),
    r_squared = summary_model$r.squared,
    sigma = summary_model$sigma
  )
}
```

Serialized as JSON.

### In T:

1. Parse JSON
2. Validate `__type__`
3. Convert numeric arrays → `Vector<Float64>`
4. Instantiate `LinearModel`

We discard:

* formula environment
* terms object
* call
* class attributes

Projection is **semantic, not structural**.

---

# 5. Python scikit-learn LinearRegression

From scikit-learn

Sandbox:

```python
def export_linear_model(model, X=None, y=None):
    return {
        "__type__": "Python.sklearn.LinearRegression",
        "coefficients": model.coef_.tolist(),
        "intercept": float(model.intercept_),
        "r_squared": model.score(X, y) if X is not None else None
    }
```

Serialized as JSON.

In T:

* Validate type
* Convert arrays
* Instantiate `LinearModel`

We ignore:

* internal solver state
* attributes not part of canonical model

---

# 6. Julia Linear Regression

Assume:

* `GLM.jl`

Sandbox:

```julia
function export_lm(model)
    Dict(
        "__type__" => "Julia.GLM.LinearModel",
        "coefficients" => coef(model),
        "intercept" => coef(model)[1],
        "r_squared" => r2(model)
    )
end
```

Serialized as JSON.

Same T-side projection.

---

# 7. Conversion Algorithm in T

Pseudo-code:

```
if payload.format == ARROW:
    return DataFrame.from_arrow(payload)

if payload.format == JSON:
    obj = parse_json(payload)

    switch obj["__type__"]:

        case "R.lm":
            return convert_r_lm(obj)

        case "Python.sklearn.LinearRegression":
            return convert_sklearn(obj)

        case "Julia.GLM.LinearModel":
            return convert_julia_lm(obj)

        default:
            return Foreign(payload)
```

---

# 8. Opaque Foreign Fallback

If JSON object:

* Has no known `__type__`
* Or conversion fails validation

Wrap as:

```t
Foreign {
  language: "R" | "Python" | "Julia"
  declared_type: string
  raw_json: JsonValue
}
```

No automatic structural recursion.

---

# 9. Validation Rules

Every projection must:

* Verify required fields
* Enforce numeric types
* Reject unexpected nested objects
* Reject reference cycles
* Reject unknown numeric precision

Fail fast.

---

# 10. No Deep Structural Conversion

Engineers must not:

* Recursively convert arbitrary JSON into nested T objects
* Attempt to mirror class hierarchies
* Preserve foreign object identity
* Attempt round-trip reconstruction

T is not a mirror runtime.

---

# 11. Versioning Strategy

Every projection must include:

```json
{
  "__type__": "R.lm",
  "__version__": 1,
  ...
}
```

T must reject unsupported versions.

---

# 12. Summary of Implementation Priorities

Phase 1:

* Arrow ingestion
* DataFrame canonical wrapper
* JSON parser
* LinearModel canonical type
* R lm projection
* Pandas ingestion

Phase 2:

* sklearn projection
* Julia DataFrame ingestion
* Julia linear model projection
* Foreign fallback wrapper

Phase 3:

* Projection registry system
* Version negotiation
* Schema evolution

---

# Final Design Philosophy

We are not importing foreign runtimes.

We are:

* Accepting structured data
* Accepting declared semantic projections
* Converting into canonical T values

Arrow handles tabular memory.
JSON handles semantic projection.
Everything else becomes opaque.

This keeps:

* T deterministic
* T language-agnostic
* T semantically coherent
* T free from foreign runtime complexity
