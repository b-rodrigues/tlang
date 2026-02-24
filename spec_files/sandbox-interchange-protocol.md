# RFC: Cross-Language Sandbox Interchange Protocol (SIP)

## Status

Draft

## Author

T Core Team

## Motivation

T executes R, Python, and Julia code in isolated Nix build sandboxes.
Currently, data must be transferred back to T using universal formats (like CSV).
However, for structured objects like models, summaries, or complex nested structures, CSV is insufficient.

We need a protocol that is:
* **Deterministic**: Same input always produces the same serialized SIP object.
* **Language-neutral**: Works across R, Python, and Julia without favoring one runtime's internal system.
* **Versioned**: Allows the T runtime to handle evolving schemas.
* **Semantically explicit**: Every object declares what it *is* in T's world.

This RFC proposes the **Sandbox Interchange Protocol (SIP)**, a JSON-based contract for exporting structured T objects from external runtimes.

---

# 1. Problem Statement

When sandboxed code returns values, we must:
1. Serialize them inside the sandbox.
2. Transfer them via the Nix store.
3. Deserialize them inside T.
4. Map them into T-native semantic objects (e.g., mapping an R `lm` object to a T `model.linear`).

Currently, T lacks a formal "interop layer" that handles the semantics of complex objects. We cannot:
* Require users to implement custom OCaml/C++ extensions to support every R package.
* Depend on runtime-specific internal formats (e.g., `.rds` for R or `pickle` for Python) as they create tight coupling.

---

# 2. Design Principles

1. **Semantic Ownership by T**: The exported object must conform to T’s type system, not the originating runtime’s.
2. **Explicit Type Annotation**: Every exported object must declare its T semantic type.
3. **Versioned Schema**: The interchange format must include version metadata.
4. **Sandbox Autonomy**: Export functions are injected into the sandbox environment by T.
5. **No Runtime Object Leakage**: Raw runtime objects (R SEXP, Python classes) must not cross the boundary.

---

# 3. Overview of the Sandbox Interchange Protocol (SIP)

All exported objects must serialize to JSON with the following top-level structure:

```json
{
  "t_type": "<semantic-type>",
  "t_version": <integer>,
  "payload": { ... },
  "meta": { ... optional ... }
}
```

### Fields

| Field       | Description                |
| ----------- | -------------------------- |
| `t_type`    | T semantic type identifier (e.g., `model.linear`, `dataframe`, `stats.summary`) |
| `t_version` | Schema version number (e.g., `1`) |
| `payload`   | Type-specific data (must be valid JSON) |
| `meta`      | Optional runtime metadata (engine version, timestamp, etc.) |

---

# 4. Implementation Sketches

## 4.1 R Exporter (R Library)

T will provide an R package (or a sourced script) injected into the Nix environment:

```r
# Provided by T's iolib.R
t_to_model_linear <- function(model, path) {
  out <- list(
    t_type = "model.linear",
    t_version = 1,
    payload = list(
      coefficients = as.list(coef(model)),
      residual_std = sigma(model),
      n_obs = nobs(model)
    ),
    meta = list(
      engine = "R", 
      engine_version = as.character(getRversion())
    )
  )
  jsonlite::write_json(out, path, auto_unbox = TRUE)
}
```

## 4.2 Python Exporter (Python Module)

Similarly, for Python nodes:

```python
# Provided by T's t_helpers module
import json

def t_to_model_linear(model, path):
    out = {
        "t_type": "model.linear",
        "t_version": 1,
        "payload": {
            "coefficients": dict(zip(model.feature_names_in_, model.coef_.tolist())),
            "residual_std": float(getattr(model, 'residual_std_', 0.0)),
            "n_obs": int(model.n_features_in_)
        },
        "meta": {"engine": "python"}
    }
    with open(path, 'w') as f:
        json.dump(out, f)
```

## 4.3 T Deserializer (OCaml)

The T evaluator will dispatch on the `t_type` field:

```ocaml
(* src/serialization.ml or new src/sip.ml *)

let deserialize_sip json_val =
  let open Yojson.Safe.Util in
  let t_type = json_val |> member "t_type" |> to_string in
  let t_version = json_val |> member "t_version" |> to_int in
  let payload = json_val |> member "payload" in

  match t_type with
  | "model.linear" ->
      (* Create a T-native representation, potentially a Dict with model.linear metadata *)
      Ast.VDict [
        ("t_class", VString "model.linear");
        ("coefficients", json_to_t_dict (member "coefficients" payload));
        ("residual_std", VFloat (payload |> member "residual_std" |> to_float));
        ("n_obs", VInt (payload |> member "n_obs" |> to_int))
      ]
  | "dataframe" ->
      (* Handle JSON-encoded dataframes or link to Arrow *)
      deserialize_dataframe_sip payload
  | _ -> 
      Ast.VError { code = TypeError; message = "Unknown SIP type: " ^ t_type; context = [] }
```

---

# 5. Usage in T Pipelines

```t
p = pipeline {
    -- The node() function can now use 'sip' as a serializer/deserializer hint
    fit_model = node(
        command = <{ 
            fit <- lm(mpg ~ cyl, data = mtcars)
        }>,
        runtime = R,
        serializer = sip -- basically a stand-in for t_to_model_linear
    )
}

m = build_pipeline(p)
res = read_node(m.fit_model)

-- res is now a T-native object:
print(res.coefficients)
```

---

# 6. Rationale Against Alternatives

* **RDS / Pickle**: No cross-language support. Extremely brittle to runtime version changes.
* **Arrow**: Excellent for tabular data, but overly complex for scalar metadata or model coefficients. SIP complements Arrow (SIP can carry an Arrow path in its payload).
* **Plain CSV**: Lacks semantic metadata. You can't distinguish between a CSV that is a "data table" and a CSV that is a "list of coefficients".

---

# 7. Next Steps

1. Implement `SIP` module in `src/`.
2. Update `iolib.R` and `iolib.py` with exporter functions.
3. Add `model.linear` as a first-class type or a recognized Dict pattern in T's `stats` package.
4. Update `build_pipeline` to support `sip` as a default interchange format when no other is specified for complex objects.
