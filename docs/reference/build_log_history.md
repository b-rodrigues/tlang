# build_log_history

Retrieve Build Log History for Pipeline

Returns a summary DataFrame of all historical builds matching the current pipeline's node signature, ordered from most recent to oldest.

## Parameters

- **pipeline** (`Pipeline`): The pipeline to retrieve history for.

- **n** (`Int`): (Optional) Limit to last N builds. Defaults to NA (no limit).

- **pattern** (`String`): (Optional) A regex pattern to filter log filenames. Defaults to NA.


## Returns

Summary DataFrame of historical builds.

