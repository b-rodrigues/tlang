# populate_pipeline

Populate Pipeline

Generates the `_pipeline/` directory with `pipeline.nix` and `dag.json`. Optionally builds the pipeline.

## Parameters

- **p** (`Pipeline`): The pipeline to populate.
- **build** (`Bool`): (Optional) Whether to trigger the Nix build immediately. Defaults to false.

## Returns

A status message or the output path if build=true.

