# populate_pipeline

Populate Pipeline

Generates the `_pipeline/` directory with `pipeline.nix` and `dag.json`. Optionally builds the pipeline with full Nix-native orchestration support.

## Parameters

- **p** (`Pipeline`): The pipeline to populate.

- **build** (`Bool`): (Optional) Whether to trigger the Nix build immediately. Defaults to false.

- **verbose** (`Int`): (Optional) Nix build verbosity level. `0` keeps build failures quiet; values above `0` print failed node logs.

- **dry_run** (`Bool`): (Optional) Perform a dry run via Nix (`--dry-run`), returning a DataFrame of planned actions without executing.

- **nix_options** (`Dict`): (Optional) A dictionary of Nix orchestration options:


## Returns

A status message, structured build log, or dry-run plan DataFrame.

