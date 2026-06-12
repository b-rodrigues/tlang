# pipeline_gc

Garbage Collect Pipeline Nodes

Calls nix-store --delete on the store paths of a pipeline's nodes.

## Parameters

- **p** (`Pipeline`): The pipeline to clean up.

- **dry_run** (`Bool`): (Optional) If `true`, only lists what would be deleted without executing the deletion. Defaults to `false`.


## Returns

A DataFrame with columns `node` (String), `store_path` (String), and `deleted` (Bool).

## Examples

```t
pipeline_gc(p, dry_run=true)
```

