# Specification: Finalizing Julia Support in T-Lang

This document outlines the remaining gaps and required implementations to bring Julia support to parity with R and Python runtimes in T-Lang.

## Current Status
- [x] Julia Companion Package (`tlang` helper) implemented with `read_node` and `pipeline_nodes`.
- [x] Basic Serializer Injections (CSV, JSON, Arrow) for Julia nodes.
- [x] Nix generator handles `JULIA_LOAD_PATH` and companion package provisioning.
- [x] Cross-language dependency wiring via `T_NODE_<name>` environment variables.

## Remaining Gaps

### 1. Robust Native Serialization
Unlike Python (which uses `dill`/`cloudpickle` fallbacks) or R (`saveRDS`), Julia currently relies on standard `Serialization.serialize`.
- **Issue**: Complex objects and models often hit "World Age" or method-caching issues across process boundaries.
- **Goal**: Implement a `jl_serialize` helper in `nix_emit_node.ml` that provides a more stable serialization path for models.

### 2. PMML & ONNX Export Support
Julia currently lacks the automated model export logic available to R and Python.
- **Requirement**: Implement `t_pmml_jl_code` and `t_onnx_jl_code` in `nix_emit_node.ml`.
- **Target Libraries**: Support `GLM.jl`, `DecisionTree.jl`, and `Flux.jl` for standardized model interchange.

### 3. Runtime Diagnostics (`t doctor`)
Diagnostic health checks for Julia environments are missing.
- **Goal**: Add checks to `package_doctor.ml` to verify:
    - `JULIA_LOAD_PATH` correctness.
    - Presence of mandatory packages (`JSON`, `DataFrames`, `CSV`, `Arrow`).
    - Basic Julia binary availability and version compatibility.

### 4. Visual Metadata Extraction
The T-Lang REPL cannot currently display rich previews for Julia plots.
- **Goal**: Add metadata extraction logic for `Makie.jl` and `Plots.jl` to enable interactive plot previews in the REPL.

### 5. CI/CD Integration Testing
Native integration tests for Julia are currently sparse in the main test suite.
- **Goal**: Add `tests/julia/test_julia_integration.ml` to ensure cross-language interchange and Julia node stability in the CI pipeline.

## Implementation Priority
1. **PMML Export**: Essential for model interoperability.
2. **Diagnostics**: Crucial for onboarding and troubleshooting.
3. **Robust Serialization**: Prevents brittle pipeline failures for complex models.
