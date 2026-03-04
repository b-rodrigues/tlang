# arrange_node

Arrange Pipeline Nodes

Returns a new pipeline with nodes sorted by a metadata field. Execution order is always determined by the DAG — this affects only the order in which nodes appear when printing or serializing the pipeline.

## Parameters

- **p** (`Pipeline`): The pipeline to sort.
- **field** (`Symbol`): The metadata field to sort by (e.g. `$depth`, `$name`).
- **direction** (`String`): (Optional) `"asc"` (default) or `"desc"`.

## Returns:

Returns: A new pipeline with nodes reordered.

## Examples

```t
p |> arrange_node($depth)
p |> arrange_node($name, "asc")
p |> arrange_node($depth, "desc")
```

## See Also

[select_node](select_node.md), [filter_node](filter_node.md)

