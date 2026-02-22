# load_node

Load Pipeline Node Artifact

Loads a node artifact by name from the latest (or specified) build log. Equivalent to `read_node`; both support `which_log` for historical access.

## Parameters

- **name** (`String`): The node name.
- **which_log** (`String`): (Optional) A regex pattern to match a specific build log filename.

## Returns

The deserialized value.

## See Also

[inspect_pipeline](inspect_pipeline.md), [read_node](read_node.md), [build_pipeline](build_pipeline.md)

