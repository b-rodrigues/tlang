# pipeline_cache_status

Check Pipeline Cache Status

Queries local Nix store validity for each node in a pipeline.

## Parameters

- **p** (`Pipeline`): The pipeline to inspect.


## Returns

A DataFrame with columns `node` (String), `cached` (Bool), and `store_path` (String).

## Examples

```t
pipeline_cache_status(p)
```

