# populate_pipeline

Populate Pipeline

Generates the `_pipeline/` directory with `pipeline.nix` and `dag.json`. Optionally builds the pipeline.

## Parameters

- **p** (`Pipeline`): The pipeline to populate.

- **build** (`Bool`): (Optional) Whether to trigger the Nix build immediately. Defaults to false.

- **verbose** (`Int`): (Optional) Nix build verbosity level. `0` keeps build failures quiet; values above `0` print failed node logs.


## Returns

A status message or the output path if build=true.

