# build_log

Retrieve Build Log for Pipeline

Returns the `BuildLog` of the latest Nix build for the given pipeline. Includes node-level status records, total duration, failed node names, and `out_path`. Use `which_log` to read from a specific historical build ("time travel").

## Parameters

- **pipeline** (`Pipeline`): The pipeline to retrieve logs for.

- **which_log** (`String`): (Optional) A regex pattern to match a specific build log filename.


## Returns



