# pipeline_to_store

Introspect Node Store Paths

Returns a dictionary mapping each node name to its low-level Nix store output path.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

A dictionary of [node_name: store_path] strings.

## Examples

```t
p = pipeline {
a = 1
}
pipeline_to_store(p)
```

