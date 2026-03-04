# upstream_of

Extract Upstream Subgraph

Returns a new pipeline containing the named node and all of its transitive dependencies (ancestors in the DAG).

## Parameters

- **p** (`Pipeline`): The pipeline.
- **name** (`String`): The name of the target node.

## Returns:

Returns: A new pipeline with only the node and its ancestors.

## Examples

```t
p |> upstream_of("predictions")
```

## See Also

[subgraph](subgraph.md), [downstream_of](downstream_of.md)

