# inspect_pipeline

Static Pipeline DAG Schema Inspection

Returns a DataFrame containing the static schema and dependencies of a pipeline's defined nodes. Never hits the filesystem or reads build logs.

## Parameters

- **p** (`Pipeline`): The pipeline object to inspect (e.g. `p = pipeline { ... }`). If called without arguments inside the T environment, it will automatically look up the bound pipeline in the current scope.

## Returns

A DataFrame with columns: `node`, `runtime`, `serializer`, `dependencies`, `has_script`.
