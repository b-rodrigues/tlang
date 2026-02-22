# read_node

Read Pipeline Node Artifact

Reads a node artifact from the latest (or specified) build log in `_pipeline/`. Use `which_log` to read from a specific historical build ("time travel").

## Parameters

- **name** (`String`): The node name.
- **which_log** (`String`): (Optional) A regex pattern to match a specific build log filename.

## Returns

The deserialized value.

## See Also

[inspect_pipeline](inspect_pipeline.md), [build_pipeline](build_pipeline.md)

