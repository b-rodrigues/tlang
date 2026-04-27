# Specification: StructuralError

## Overview
This specification introduces a new category of error in T-Lang: the `StructuralError`. Unlike standard `VError` values which are treated as first-class data in "Resilient-by-Default" mode, a `StructuralError` represents a fundamental failure in the project's orchestration, dependency graph, or environment.

**Core Principle**: Structural integrity is required for resilient evaluation to be meaningful. You cannot handle errors as values if the value's path is structurally impossible.

---

## 1. Classification
A `StructuralError` is defined as any error that prevents the valid construction, materialization, or execution of a pipeline's DAG (Directed Acyclic Graph).

### Key Categories:
1.  **Graph Topology Failures**:
    *   **Cyclical Dependencies**: Node A -> Node B -> Node A.
    *   **Missing Node References**: Node A depends on `user_data_bis`, but only `user_data` exists in the pipeline.
2.  **Inter-Node Coherence Failures**:
    *   **Serialization Mismatch**: Node A produces ^arrow but Node B (a consumer) explicitly requests ^pmml for that dependency.
    *   **Arity/Signature Mismatch in Pipeline Context**: Calling a pipeline node with the wrong number of arguments in a task-style node definition.
3.  **Infrastructure Failures**:
    *   **Missing Tooling**: `nix-build` or `arrow-glib` not found in the environment.
    *   **Project Config Violations**: `tproject.toml` is missing, malformed, or lacks the mandatory dependencies for the requested serializers.
    *   **Unsatisfied Dependencies**: Pipeline nodes require packages (e.g., `arrow`, `pyarrow`, `onnx`) that are missing from `tproject.toml` and cannot be automatically injected.
        *   If `TLANG_AUTO_ADD_PIPELINE_DEPS=1` is set, T-Lang will attempt to update `tproject.toml` automatically.
        *   If the update fails, is declined by the user, or cannot proceed (e.g., non-interactive session without the flag), a `StructuralError` is raised.
    *   **Materialization Failures**: Failure to write to `_pipeline/` or generate the `pipeline.nix` entry.

---

## 2. Behavioral Semantics: The "Loud Failure"
The primary difference between a `StructuralError` and a standard `VError` is how the Evaluator (runner) handles it during program execution.

### Evaluation Rules:
- **Resilient Mode (`resilient=true`)**: Standard errors (e.g., `DivisionByZero`, `NameError`, `ValueError`) are returned as values and execution continues.
- **Structural Exception**: If a statement or expression evaluates to a `VError` with the code `StructuralError`, **evaluation must halt immediately**, regardless of the resilience setting.

### Rationale:
In the "Resilient-by-Default" model, we allow scripts to continue so users can see full diagnostic summaries. However, if a structural error occurs (e.g., `populate_pipeline` fails due to a missing dependency), letting the script continue leads to "cascading gibberish"—where subsequent steps fail for confusing reasons (like "logs not found") rather than the original structural cause.

---

## 3. Integration with Builtins
The following builtins will be updated to emit `StructuralError` instead of `FileError` or `ValueError` in specific cases:

| Builtin | Condition | Previous Error | New Error |
|---|---|---|---|
| `pipeline { ... }` | Dependency Cycle | `ValueError` | `StructuralError` |
| `pipeline { ... }` | Reference to missing node | `NameError`/`KeyError` | `StructuralError` |
| `populate_pipeline` | Missing tool (`nix-build`) | `FileError` | `StructuralError` |
| `populate_pipeline` | Serializer Coherence Failure | `FileError` | `StructuralError` |
| `populate_pipeline` | Missing dependencies in `tproject.toml` | `FileError` | `StructuralError` |

---

## 4. User Experience (UX)
When a `StructuralError` is encountered, the T-Lang runner should provide a distinct visual treatment:

```text
✖ FATAL STRUCTURAL ERROR: [src/pipeline.t:L143] 
  Pipeline requires explicit dependencies in `tproject.toml` before it can be built.
  Missing entries: [py-dependencies] packages += ["pyarrow"]
  
Building halted. (Structural errors bypass resilient evaluation)
```

---

## 5. Summary of Impacts
- **Evaluator**: `eval_program` must be updated to detect the `StructuralError` code and trigger an early return.
- **Diagnostics**: `StructuralError` should carry rich context (e.g., the missing node name, or the specific serializer mismatch).
- **Existing Demos**: Projects with structurally invalid `tproject.toml` files will now fail loudly and correctly, rather than failing silently and confusingly in downstream steps.
