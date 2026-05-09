# Specification: Julia Runtime Support in T-Lang

This document describes the integration of Julia as a first-class runtime for T-Lang pipeline nodes.

## 1. Overview

Julia support allows users to execute Julia code within pipeline nodes, passing data back and forth using standard serializers and model interchange helpers (CSV, JSON, Arrow, PMML, ONNX).

### Node Constructor: `jl_node`

A new convenience constructor `jl_node` has been added. It is equivalent to `node(runtime = Julia, ...)`.

```t
p = pipeline {
  # Inline command
  calc = jl_node(command = <{ 
    using DataFrames
    df = DataFrame(x = [1, 2, 3])
    df.y = df.x .* 10
    df
  }>, serializer = ^arrow)

  # From script
  train = jl_node(script = "src/train.jl", serializer = ^json)
}
```

## 2. Dependency Management

Julia dependencies and versions are managed via `tproject.toml`.

### `[julia-dependencies]` Section

Users can specify the Julia version and required packages:

```toml
[julia-dependencies]
version = "1.11"
packages = ["DataFrames", "CSV", "Arrow", "JSON"]
```

- **`version`**: 
  - A string like `"1.11"` maps to `pkgs.julia_1_11`.
  - `"lts"` maps to `pkgs.julia_lts`.
  - Default is `"lts"`.
- **`packages`**: A list of Julia packages to be installed in the environment.

## 3. Serialization

### Supported Serializers

| Format | T Constructor | Julia Helper Functions |
|--------|---------------|------------------------|
| CSV    | `^csv`        | `jl_write_csv(df, path)`, `jl_read_csv(path)` |
| JSON   | `^json`       | `jl_write_json(obj, path)`, `jl_read_json(path)` |
| Arrow  | `^arrow`      | `jl_write_arrow(df, path)`, `jl_read_arrow(path)` |
| PMML   | `^pmml`       | `jl_write_pmml(model, path)`, `jl_read_pmml(path)` |
| ONNX   | `^onnx`       | `jl_write_onnx(path, model)`, `jl_read_onnx(path)` |

## 4. Implementation Details

### Extended Files

- **`src/eval.ml`**: 
  - Registered `jl_node` as a pipeline constructor.
  - Added `Julia` to `known_symbols`.
  - Fixed `DotAccess` for `VNodeResult` to expose the `.value` field.
- **`src/pipeline/nix_emit_pipeline.ml`**:
  - Added logic to parse `julia-dependencies` and inject `juliaPkg` into the Nix build environment.
- **`src/pipeline/nix_emit_node.ml`**:
  - Implemented helper injection for `jl_write_csv`, `jl_read_csv`, etc.
  - Added Julia to the runtime pattern matches.
- **`src/package_manager/toml_parser.ml`**:
  - Added support for parsing and serializing the `[julia-dependencies]` section.
- **`editors/tree-sitter-t/queries/highlights.scm`**:
  - Added `jl_node` to builtin function highlights.

### Verification

- **Unit Tests**: `tests/pipeline/test_pipeline.ml` verifies the `jl_node` constructor and `DotAccess` logic.
- **Golden Tests**: `tests/golden/t_scripts/julia_simple.t` provides an end-to-end integration test comparing Julia output with expected R output.

## 5. Future Work & Next Steps

- **Dependency Tracking**: Refine `pipeline_dependency_requirements.ml` to support automatic detection of missing Julia packages in `tproject.toml`, mirroring the logic used for R and Python.
- **Internal Helper Registration**: Ensure `jl_node` (along with `node`, `pyn`, and `rn`) is formally registered in the standard package registry in `src/packages/core/packages.ml` for improved discoverability via `packages()` and `help()`.
- **Error Diagnostics**: Enhance error reporting for Julia runtime errors by capturing and formatting Julia-native stack traces into T-Lang's structured error format.
- **Test Integrity**: Continue monitoring pipeline artifact deserialization. A known issue with `DotAccess` on `VNodeResult` was identified and fixed during initial integration, ensuring that `.value` access works correctly on recovered nodes.
