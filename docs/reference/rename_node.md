# rename_node

Rename a Pipeline Node

Renames a single node and rewires all dependency edges that referenced the old name to the new name. This is the canonical way to resolve name collisions before set operations.

## Parameters

- **p** (`Pipeline`): The pipeline.
- **old_name** (`String`): The current name of the node.
- **new_name** (`String`): The desired new name.

## Returns:

Returns: A new pipeline with the node renamed.

## Examples

```t
p |> rename_node("model_r", "model_r_v2")
```

## See Also

[filter_node](filter_node.md), [mutate_node](mutate_node.md)

