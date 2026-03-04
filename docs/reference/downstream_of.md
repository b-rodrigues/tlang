# downstream_of

Extract Downstream Subgraph

Returns a new pipeline containing the named node and all nodes that transitively depend on it (descendants in the DAG).

## Parameters

- **p** (`Pipeline`): The pipeline.
- **name** (`String`): The name of the target node.

## Returns:

Returns: A new pipeline with only the node and its descendants.

## Examples

```t
p |> downstream_of("data")
```

## See Also

[subgraph](subgraph.md), [upstream_of](upstream_of.md)

