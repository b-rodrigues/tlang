# read_node

Read Pipeline Node Artifact

For in-memory Pipelines, returns a node record with the node value and structured diagnostics. For built pipelines, reads the artifact from the latest (or specified) build log in `_pipeline/`. Use `which_log` to read from a specific historical build ("time travel").

## Parameters

- **node** (`Pipeline`): | String | ComputedNode Pass a Pipeline for in-memory node diagnostics, or a String/ComputedNode to load a built artifact.

- **name** (`String`): (Optional) The node name to read when `node` is a Pipeline.

- **which_log** (`String`): (Optional) A regex pattern to match a specific build log filename.


## Returns

A Dict with value+diagnostics for in-memory pipelines, or the deserialized artifact for built nodes.

## See Also

[inspect_pipeline](inspect_pipeline.html), [build_pipeline](build_pipeline.html), [read_pipeline](read_pipeline.html)

