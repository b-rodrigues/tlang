# Specification: Finalizing Julia Support in T-Lang

This document outlines the remaining gaps and required implementations to bring Julia support to parity with R and Python runtimes in T-Lang.

## Current Status
- [x] Julia Companion Package (`tlang` helper) implemented with `read_node` and `pipeline_nodes`.
- [x] Basic Serializer Injections (CSV, JSON, Arrow) for Julia nodes.
- [x] Nix generator handles `JULIA_LOAD_PATH` and companion package provisioning.
- [x] Cross-language dependency wiring via `T_NODE_<name>` environment variables.

## Remaining Gaps (Revalidated)

### 1. Robust Native Serialization
**Status:** Partially implemented.

Julia runtime injection now includes `jl_serialize(obj, path)` in `nix_emit_node.ml`, and it is wired into serialization dispatch for Julia nodes.

- **Still open:** `jl_serialize` currently delegates directly to `Serialization.serialize(path, obj)`.
- **Potential risk:** complex objects and models may still hit world-age/method-cache issues across process boundaries.
- **Next step:** harden `jl_serialize` with a more robust model-safe strategy (or explicitly document unsupported object classes).

### 2. PMML & ONNX Export Support
**Status:** Largely implemented in `nix_emit_node.ml`.

- `t_pmml_jl_code` is implemented, including a GLM-focused PMML writer and a JPMML-backed reader.
- `t_onnx_jl_code` is implemented with ONNX/ONNXRunTime based read/write helpers.
- **Remaining gap:** model-family coverage and interoperability hardening (e.g., validate end-to-end support expectations for non-GLM models such as `DecisionTree.jl` and `Flux.jl`).

### 3. Runtime Diagnostics (`t doctor`)
**Status:** ~~Still a gap~~.

`t doctor` exists, but `package_doctor.ml` does not yet perform Julia-specific runtime diagnostics.
- **Goal**: Add checks to `package_doctor.ml` to verify:
    - `JULIA_LOAD_PATH` correctness.
    - Presence of mandatory packages (`JSON`, `DataFrames`, `CSV`, `Arrow`).
    - Basic Julia binary availability and version compatibility.

### 4. Visual Metadata Extraction
**Status:** Implemented for core Julia plot cases.

Metadata extraction and preview plumbing for Julia plot classes (including Makie-focused handling) exists in pipeline emission, and `show_plot` includes Julia rendering logic with explicit `CairoMakie` requirements for Makie.

- **Possible follow-up:** expand extraction coverage and metadata richness for additional plotting packages/types.

### 5. CI/CD Integration Testing
**Status:** Partially addressed through existing suite coverage.

There is already Julia-related coverage in the pipeline and CLI test suites (including Julia plot metadata/renderer behavior), but a dedicated `tests/julia/test_julia_integration.ml` target still does not exist.

- **Goal:** optionally add a dedicated Julia integration test file if clearer ownership/isolation is desired in CI.

## Updated Implementation Priority
~~1. **Diagnostics (`t doctor`)**: still missing Julia-specific checks and is the clearest operational gap.~~
2. **Serialization hardening**: `jl_serialize` exists but is still thin and should be made more robust/documented.
3. **Interoperability hardening for PMML/ONNX**: core helpers exist; prioritize broader model-family validation and tests.
