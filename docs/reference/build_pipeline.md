# build_pipeline

Build Pipeline Artifacts

Builds a pipeline to `pipeline.nix` and records node artifacts in a local registry.

## Parameters

- **p** (`Pipeline`): The pipeline to build.

- **verbose** (`Int`): (Optional) Nix build verbosity level. `0` keeps build failures quiet; values above `0` print failed node logs.


## Returns

The output path (Nix store path or local fallback directory).

## See Also

[read_node](read_node.html)

