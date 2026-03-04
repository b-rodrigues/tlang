# subgraph

Extract Connected Subgraph

Returns a new pipeline containing the named node, all of its ancestors, and all of its descendants — the full connected component reachable from the node in either direction.

## Parameters

- **p** (`Pipeline`): The pipeline.
- **name** (`String`): The name of the target node.

## Returns:

Returns: A new pipeline with the full connected component.

## Examples

```t
p |> subgraph("model_r")
```

## See Also

[downstream_of](downstream_of.md), [upstream_of](upstream_of.md)

