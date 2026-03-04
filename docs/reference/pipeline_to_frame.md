# pipeline_to_frame

Convert Pipeline to DataFrame

Converts a Pipeline to a DataFrame where each row represents a node and each column represents a metadata field. This is a key inspection utility for understanding and debugging pipeline structure.  The columns returned are: - `name` — the node name (String) - `runtime` — one of "T", "R", "Python" (String) - `serializer` — e.g. "default", "pmml" (String) - `deserializer` — e.g. "default", "pmml" (String) - `noop` — whether the node is a no-op (Bool) - `deps` — names of nodes this node depends on (String, comma-separated) - `depth` — topological depth in the DAG (Int); roots are depth 0 - `command_type` — one of "command" or "script" (String)

## Parameters

- **p** (`Pipeline`): The pipeline to convert.

## Returns:

Returns: A DataFrame with one row per node.

## Examples

```t
pipeline_to_frame(p)
```

## See Also

[pipeline_nodes](pipeline_nodes.md), [select_node](select_node.md)

