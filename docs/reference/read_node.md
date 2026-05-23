# read_node

Read Pipeline Node Artifact

Reads and returns the contents of a ComputedNode. For in-memory pipelines, returns the dynamically computed value directly from the registry. For built pipelines, reads the materialized artifact from the latest (or specified) build log. Use `which_log` to read from a specific historical build ("time travel").

## Parameters

- **node** (`ComputedNode`): The ComputedNode object to read (e.g. `p.node_name`).

- **which_log** (`String`): (Optional) A regex pattern to match a specific build log filename.


## Returns

The deserialized artifact value, or the in-memory value.

## See Also

[inspect_pipeline](inspect_pipeline.html), [build_pipeline](build_pipeline.html), [read_pipeline](read_pipeline.html)

