# build_pipeline

Build Pipeline Artifacts

Builds a pipeline to `pipeline.nix` and records node artifacts in a local registry. Supports Nix-native orchestration flags for targeted builds, cache usage, and dry-runs. If the pipeline contains unexpanded dynamic branching patterns (`map_pattern`, `cross_pattern`), they are automatically expanded before building.

## Parameters

- **pipeline** (`Pipeline`): The pipeline to build.

- **verbose** (`Int`): (Optional) Nix build verbosity level. `0` keeps build failures quiet; values above `0` print failed node logs.

- **nix_options** (`Dict`): (Optional) A dictionary of Nix orchestration options:


## Returns

A structured build log (`nodes`, `duration`, `failed_nodes`, `out_path`), or a dry-run DataFrame.

## See Also

[read_node](read_node.html)

