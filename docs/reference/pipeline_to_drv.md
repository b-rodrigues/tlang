# pipeline_to_drv

Introspect Node Derivation Paths

Returns a dictionary mapping each node name to its low-level Nix store derivation (.drv) path.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

A dictionary of [node_name: drv_path] strings.

## Examples

```t
p = pipeline {
a = 1
}
pipeline_to_drv(p)
```

