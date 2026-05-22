# inspect_log

Inspect Pipeline Build Logs

Reads the latest (or specified) Nix build log on the filesystem and returns a DataFrame showing the dynamic execution status.

## Parameters

- **which_log** (`String`): (Optional) A regex pattern to match a specific build log filename in `_pipeline/`.

## Returns

A DataFrame with columns: `derivation`, `build_success`, `path`, `output`.
