# read_node

Read Pipeline Node Artifact

Reads and returns the contents of a ComputedNode. For in-memory pipelines, returns the dynamically computed value directly from the registry. For built pipelines, reads the materialized artifact from the latest build log.  Note: The `.warnings` field previously returned on the result has been removed. Use `warning_msg(node)` to inspect a node's own warnings and any upstream warnings inherited from ancestor nodes. Use `inspect_node(node)` for structured warning metadata.  Use `read_past_node(p.node_name, which_log = "...")` to read a node from a specific historical build log without needing the pipeline in scope.

## Parameters

- **node** (`ComputedNode`): The ComputedNode object to read (e.g. `p.node_name`).


## Returns

The deserialized artifact value, or the in-memory value.

## See Also

[inspect_pipeline](inspect_pipeline.html), [build_pipeline](build_pipeline.html), [read_pipeline](read_pipeline.html), [inspect_node](inspect_node.html), [warning_msg](warning_msg.html), [read_past_node](read_past_node.html)

