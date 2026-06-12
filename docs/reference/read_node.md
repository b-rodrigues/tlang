# read_node

Read Pipeline Node Artifact

Reads and returns the contents of a ComputedNode. For in-memory pipelines, returns the dynamically computed value directly from the registry. For built pipelines, reads the materialized artifact from the latest build log.

> **Note:** The `.warnings` field previously accessible on the result of `read_node()` has been removed. Use [`warning_msg(node)`](warning_msg.html) to inspect warnings. Use [`inspect_node(node)`](inspect_node.html) for structured warning metadata.
>
> To read a node from a specific historical build log **without the pipeline being in scope**, use [`read_past_node(p.node_name, which_log = "...")`](read_past_node.html).
>
> **Hint on syntax errors:** If you pass a bare symbol (e.g. `read_node(ha)` instead of `read_node(p.ha)`), T will suggest the correct form: *Did you mean `read_node(p.ha)`?*

## Parameters

- **node** (`ComputedNode`): The ComputedNode object to read (e.g. `p.node_name`).


## Returns

The deserialized artifact value, or the in-memory value.

## See Also

[read_past_node](read_past_node.html), [warning_msg](warning_msg.html), [inspect_node](inspect_node.html), [inspect_pipeline](inspect_pipeline.html), [build_pipeline](build_pipeline.html), [read_pipeline](read_pipeline.html)

