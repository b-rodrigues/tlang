# ONNX Serializer for T

## What is ONNX?

**ONNX (Open Neural Network Exchange)** is an open standard format for representing machine learning models. It was developed collaboratively by Microsoft, Meta, and others, and is now maintained by the Linux Foundation AI & Data. ONNX defines a common graph-based IR (intermediate representation) and a set of built-in operators that cover a wide range of model architectures, from classical machine learning (linear models, tree ensembles, SVMs, gradient boosting) to deep neural networks.

Key properties of ONNX:

* **Language-agnostic**: models can be exported from R, Python (PyTorch, TensorFlow, scikit-learn, XGBoost, LightGBM), and re-used in any runtime that has an ONNX executor.
* **Runtime-agnostic**: the ONNX Runtime (`onnxruntime`) is a high-performance inference engine that runs on CPU and GPU and is available for OCaml (via C bindings), R, and Python.
* **Strongly typed and schema-aware**: inputs and outputs are typed tensors with known shapes, making static coherence checks straightforward.
* **Broad model coverage**: supports neural networks, gradient boosting (XGBoost, LightGBM), random forests, SVMs, linear regression, logistic regression, and feature preprocessing pipelines.

The relationship to PMML: PMML is T's current interchange format for classical statistical models (linear models, GLMs, tree ensembles). ONNX covers the same classical models and additionally covers deep learning models that PMML cannot represent. For models that both standards cover, ONNX is generally preferred because the ONNX Runtime executor is faster than T's hand-written PMML interpreter and the export tooling is more actively maintained.

---

## Why Add ONNX as a T Serializer?

| Capability | PMML | ONNX |
|---|---|---|
| Linear / GLM | ✓ | ✓ |
| Random Forest | ✓ | ✓ |
| XGBoost / LightGBM | partial | ✓ |
| Neural networks | ✗ | ✓ |
| Preprocessing pipelines | partial | ✓ (via `sklearn-onnx` pipelines) |
| Fast native inference | custom eval | ONNX Runtime (C library) |
| Active tooling ecosystem | maintenance mode | actively developed |

Adding `"onnx"` as a T serializer keyword enables:

```t
model = node(
    command = <{
        from sklearn.linear_model import LogisticRegression
        import numpy as np
        clf = LogisticRegression().fit(X, y)
    }>,
    runtime = Python,
    serializer = ^onnx
)

predictions = node(
    command = <{ predict(data, model) }>,
    runtime = T,
    deserializer = [data: ^arrow, model: ^onnx]
)
```

---

## How PMML is Currently Registered as a Serializer

Understanding the PMML path is the prerequisite for adding ONNX. The relevant call sites are:

### 1. `src/serialization_registry.ml`

Each built-in format is registered by calling `init_builtins`, which calls `mk_ser` for each format name. `mk_ser` creates a `VSerializer` record containing:

* `s_format` — the string identifier (`"pmml"`)
* `s_writer` / `s_reader` — T-native stubs (raise `RuntimeError` with a helpful message; PMML has no T-native implementation)
* `s_r_writer` / `s_r_reader` — names of the R helper functions injected at build time (`"r_write_pmml"`, `"r_read_pmml"`)
* `s_py_writer` / `s_py_reader` — names of the Python helper functions injected at build time (`"py_write_pmml"`, `"py_read_pmml"`)

Adding `"onnx"` requires:

```ocaml
| "onnx" -> (Some "r_write_onnx", Some "r_read_onnx", Some "py_write_onnx", Some "py_read_onnx")
```

and appending `"onnx"` to the `List.iter` call at the bottom of `init_builtins`.

### 2. `src/pipeline/nix_emit_node.ml`

This file contains:

* **R helper code** injected as a string literal (`t_pmml_r_code`) when any node in the pipeline uses `"pmml"` as its serializer or deserializer.
* **Python helper code** injected similarly (`t_pmml_py_code`).
* A **JRE dependency guard**: PMML export in both R and Python requires a JVM (`pkgs.jre`). This is detected by `is_pmml_ser || is_pmml_des` and added to the Nix derivation inputs.
* **Dispatch tables** for read and write functions, keyed by `(runtime, format)`:

```ocaml
| "R" -> [ ...; "pmml", "r_read_pmml"; ... ]
| "Python" -> [ ...; "pmml", "py_read_pmml"; ... ]
| _ -> [ ...; "pmml", "t_read_pmml"; ... ]
```

Adding ONNX means:
1. Writing `t_onnx_r_code` (R helpers) and `t_onnx_py_code` (Python helpers) string literals.
2. Adding `is_onnx_ser` / `is_onnx_des` guards (ONNX Runtime is a native library, no JVM needed).
3. Extending the dispatch tables with `"onnx"` entries.
4. Creating an `onnx_injection` value (same pattern as `pmml_injection`).

### 3. `src/packages/stats/t_read_pmml.ml`

This file provides T's native PMML *reader* — it parses the PMML XML and reconstructs a `VModel` value that `predict()` can consume. The equivalent for ONNX would be `t_read_onnx.ml`, which would:

1. Load the `.onnx` file via OCaml bindings to the ONNX Runtime C API.
2. Return a `VModel` wrapping an `OnnxSession` handle.
3. Hook into `predict()` so that when the model argument is a `VModel (OnnxModel …)`, it calls `OnnxRuntime.run session inputs`.

---

## Implementation Plan

### Phase 1 — Export Helpers (R and Python)

Implement `t_onnx_r_code` and `t_onnx_py_code` string literals in `nix_emit_node.ml`.

**R helpers** (`r_write_onnx`, `r_read_onnx`):

Add the `onnx` R package to the Nix flake.

```r
r_write_onnx <- function(object, path) {
  # Uses the 'onnx' R package (CRAN) which wraps torch::onnx_export for torch
  # models, or 'r2pmml' → 'onnx' conversion for classical models.
  # For classical R models (lm, glm, randomForest, xgboost):
  #   Use the 'tidypredict' / 'treesnip' + 'torch' path, or
  #   use 'r-onnx' (https://github.com/retostauffer/r-onnx) once stable.
  # Fallback: convert via sklearn2onnx by serialising through Arrow first.
  if (!requireNamespace("onnx", quietly = TRUE))
    stop("Package 'onnx' is required for ONNX serialization from R.")
  onnx::onnx_save_model(object, path)
}

r_read_onnx <- function(path) {
  # ONNX models loaded in R are used only for validation / inspection.
  # Actual inference is performed by T's ONNX Runtime bindings.
  if (!requireNamespace("onnx", quietly = TRUE))
    stop("Package 'onnx' is required for ONNX deserialization in R.")
  onnx::onnx_load_model(path)
}
```

**Python helpers** (`py_write_onnx`, `py_read_onnx`):

Add the requires Onnx Python packages to the flake.

```python
def py_write_onnx(model, path):
    """Export a fitted model to ONNX format."""
    import numpy as np

    # scikit-learn models via skl2onnx
    try:
        from skl2onnx import convert_sklearn
        from skl2onnx.common.data_types import FloatTensorType
        n_features = _infer_n_features(model)
        initial_types = [("input", FloatTensorType([None, n_features]))]
        onnx_model = convert_sklearn(model, initial_types=initial_types)
        with open(path, "wb") as f:
            f.write(onnx_model.SerializeToString())
        return path
    except ImportError:
        pass

    # PyTorch models via torch.onnx.export
    try:
        import torch
        dummy = _make_dummy_input(model)
        torch.onnx.export(model, dummy, path, opset_version=17)
        return path
    except ImportError:
        pass

    raise RuntimeError(
        "ONNX export in Python requires 'skl2onnx' (for scikit-learn models) "
        "or 'torch' (for PyTorch models). Install the appropriate package."
    )


def py_read_onnx(path):
    """Load an ONNX model for inference via onnxruntime."""
    try:
        import onnxruntime as rt
        return rt.InferenceSession(path)
    except ImportError:
        raise RuntimeError(
            "ONNX deserialization requires 'onnxruntime'. "
            "Install it with: pip install onnxruntime"
        )
```

### Phase 2 — Serialization Registry

In `src/serialization_registry.ml`, extend the `mk_ser` format match:

```ocaml
| "onnx" -> (Some "r_write_onnx", Some "r_read_onnx", Some "py_write_onnx", Some "py_read_onnx")
```

Append `"onnx"` to the `List.iter` call at the bottom of `init_builtins`:

```ocaml
List.iter (fun name -> register name (mk_ser name))
  ["csv"; "arrow"; "json"; "pmml"; "onnx"; "tlang"; "bin"; "text"]
```

### Phase 3 — Nix Emit Node Wiring

In `src/pipeline/nix_emit_node.ml`:

1. Add `t_onnx_r_code` and `t_onnx_py_code` string literals (as shown in Phase 1).
2. Add detection guards (no JVM needed, but `onnxruntime` Python package / `onnx` R package must be available in the sandbox):
   ```ocaml
   let is_onnx_ser = is_ser "onnx" in
   let is_onnx_des = is_fmt_in_des "onnx" in
   ```
3. Create an `onnx_injection`:
   ```ocaml
   let onnx_injection = make_injection
     ~enabled:(is_onnx_ser || is_onnx_des)
     ~r_code:t_onnx_r_code
     ~py_code:t_onnx_py_code
   in
   ```
4. Extend the read/write dispatch tables:
   ```ocaml
   | "R" -> [ ...; "onnx", "r_read_onnx"; ... ]
   | "Python" -> [ ...; "onnx", "py_read_onnx"; ... ]
   | _ -> [ ...; "onnx", "t_read_onnx"; ... ]
   ```
5. Pass `onnx_injection` through to the Nix derivation template (same pattern as `pmml_injection`).

### Phase 4 — T-Native ONNX Reader (`src/packages/stats/t_read_onnx.ml`)

Add OCaml bindings to `onnxruntime` (the C API) via a new stub file in `src/ffi/`. The reader function:

1. Calls `OnnxRuntime.create_session path` to load the model.
2. Returns `VModel (OnnxModel { session; input_names; output_names })`.

Extend `predict.ml` to handle `VModel (OnnxModel …)`:

```ocaml
| VModel (OnnxModel { session; input_names; _ }) ->
    let input_tensor = dataframe_to_onnx_tensor df in
    let outputs = OnnxRuntime.run session [input_tensor] in
    onnx_tensor_to_vector outputs.(0)
```

The `OnnxRuntime` module lives in `src/arrow/onnx_runtime.ml` (following the same pattern as `src/arrow/arrow_compute.ml`).

### Phase 5 — Known Symbols and `known_symbols`

ONNX does not require a new `VSymbol` entry — `^onnx` is used in node arguments, identical to `^pmml`. No changes to `src/packages/core/packages.ml` are needed.

### Phase 6 — Tests

* **Unit tests** (`tests/unit/test_onnx_serializer.ml`): verify registry lookup, `VSerializer` record structure, and that the injection guard fires correctly.
* **Integration test**: a two-node pipeline where a Python node trains a scikit-learn `LinearRegression`, exports via `py_write_onnx`, and a T node loads it via `t_read_onnx` and calls `predict()`. Compare predictions against the Python baseline.

---

## Dependency Notes

| Component | Dependency | Notes |
|---|---|---|
| Python export (sklearn) | `skl2onnx` | pip; must be in the Python sandbox derivation |
| Python export (PyTorch) | `torch` | pip; large; optional |
| Python inference | `onnxruntime` | pip; lightweight CPU executor |
| R export | `onnx` (CRAN) | experimental; alternative is `reticulate` + `skl2onnx` |
| R inference | `onnxruntime` (CRAN) | wraps the same C library |
| T / OCaml inference | `onnxruntime` C API | new FFI stubs needed in `src/ffi/` |
| Nix | no JVM needed | unlike PMML, ONNX Runtime is a native C library |

---

## Comparison with the PMML Path

| Step | PMML | ONNX |
|---|---|---|
| R export | `r2pmml::r2pmml()` (wraps JPMML, needs JVM) | `onnx::onnx_save_model()` (native) |
| Python export | `sklearn2pmml` (needs JVM) or `pypmml` | `skl2onnx.convert_sklearn()` (pure Python) |
| T reader | hand-written XML parser in `pmml_utils.ml` | `onnxruntime` C API via FFI |
| T evaluator | custom eval loop in `predict.ml` | ONNX Runtime handles eval |
| JVM required | yes | no |
| Deep learning | no | yes |

The key implementation difference is in Phase 4: PMML requires a hand-written evaluator (currently ~1500 lines across `pmml_utils.ml` and `predict.ml`), whereas ONNX delegates evaluation entirely to the ONNX Runtime C library. This makes the T-side ONNX reader simpler to implement and maintain, at the cost of adding a C FFI dependency.
