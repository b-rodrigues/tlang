# Debugging PMML Deserialization in Python Nodes

This document outlines the investigation and resolution of an `AttributeError` encountered when using PMML-serialized models within Python nodes in a T-Lang pipeline.

## Symptom
A Python node (e.g., `pred_py_r`) fails during model prediction with the following error:
```traceback
AttributeError: 'str' object has no attribute 'predict'
```

## Diagnosis

### 1. Incomplete Dependency Injection
T-Lang has an automated mechanism in `src/pipeline/pipeline_dependency_requirements.ml` that detects the use of specific serializers/deserializers and ensures the required guest runtime packages are present in `tproject.toml`.

For PMML in Python, the detection logic currently only includes:
- `numpy`, `pandas`, `scikit-learn`, `scipy`, `sklearn2pmml`, `statsmodels`
- Additional tools: `jre` (Java Runtime Environment)

**Crucially, `pypmml` is missing from this list.** While `sklearn2pmml` is excellent for *writing* PMML, it does not provide the capability to *read* a PMML file back into an executable model object. For that, the `pypmml` package (a Python wrapper for the JPMML library) is required.

### 2. Silent Engine Fallback
The T-Lang engine contains a bug in its PMML loading helper for Python (`src/pipeline/nix_emit_node.ml`). The implementation of `py_read_pmml` incorrectly performs a silent fallback to returning the raw path string if the `pypmml` package cannot be imported:

```python
def py_read_pmml(path):
    try:
        from pypmml import Model
    except ImportError:
        return path # <--- Silent fallback masks the missing dependency
    return Model.load(path)
```

Because of this fallback, the node receives a `str` (the path) instead of a `Model` object. When the node script inevitably calls `.predict()` on this string, Python throws the `AttributeError`.

## Study: `sklearn2pmml` vs `pypmml`

### `sklearn2pmml`
- **Purpose**: Conversion of trained scikit-learn models to PMML format.
- **Workflow Role**: Required by T-Lang nodes that **produce** (serialize) a model using the `^pmml` format.
- **Dependencies**: Requires a JDK/JRE and various Java libraries under the hood.

### `pypmml`
- **Purpose**: Loading and scoring PMML models.
- **Workflow Role**: Required by T-Lang nodes that **consume** (deserialize) a model using the `^pmml` format.
- **Dependencies**: Also requires a JRE.

### Conclusion
A robust T-Lang PMML implementation for Python must include **both** packages in its automated dependency injection list to ensure that models can be both produced and consumed across different nodes without manual intervention.

## Required Fixes

1.  **Engine Robustness**: Remove the silent fallback in `py_read_pmml` (within `src/pipeline/nix_emit_node.ml`) and replace it with a descriptive `RuntimeError` that instructs the user to install `pypmml`.
2.  **Dependency Checker Update**: Add `pypmml` to the `Python/pmml` requirement section in `src/pipeline/pipeline_dependency_requirements.ml`.
3.  **Project Update**: Add `pypmml` to the `py-dependencies` of the `onnx_exchange_t` project in its `tproject.toml`.

## Post-Fix Verification Plan
- Clear the `_pipeline` directory.
- Run the `onnx_exchange_t` pipeline.
- Verify that T-Lang prompts to add `pypmml` to `tproject.toml` if it is missing.
- Verify that `pred_py_r` successfully loads the PMML model and produces predictions.
