# inspect_pipeline

Inspect Pipeline Logs

Reads the latest (or specified) build log and returns a DataFrame showing the pipeline status.

## Parameters

- **which_log** (`String`): (Optional) A regex pattern to match a specific build log filename.

## Returns

A DataFrame with columns: derivation, build_success, path, output.

