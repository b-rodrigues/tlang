# select_node

Select Node Metadata Fields

Returns a DataFrame summarising the requested metadata fields for all nodes in the pipeline. This is a read-only inspection operation — it does not return a Pipeline.  Available fields: `$name`, `$runtime`, `$serializer`, `$deserializer`, `$noop`, `$deps`, `$depth`, `$command_type`.

## Parameters

- **p** (`Pipeline`): The pipeline to inspect.
- **...** (`Symbol`): One or more metadata field references (e.g. `$name`, `$runtime`).

## Returns:

Returns: A DataFrame with the requested metadata columns.

## Examples

```t
p |> select_node($name, $runtime, $deps)
p |> select_node($name, $depth, $noop)
```

## See Also

[arrange_node](arrange_node.md), [filter_node](filter_node.md), [pipeline_to_frame](pipeline_to_frame.md)

