# build_pipeline_internal

Build Pipeline Internally

Calls `nix-build` on the generated `pipeline.nix` file. Extracts the store path of the result and saves a build log with an exact mapping of node names to artifact paths in the Nix store.

## Parameters

- **p** (`PipelineResult`): The pipeline AST structure.

## Returns

The output Nix store path or an error string.

