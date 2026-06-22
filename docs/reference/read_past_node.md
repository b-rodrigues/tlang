# read_past_node

Read Pipeline Node from a Past Build Run

Reads and returns the contents of a pipeline node from a historical build log, identified by `which_log`. Unlike `read_node`, this works without the pipeline being in scope — the node name is captured via NSE from the `p.node_name` syntax.

## Parameters

- **node** (`ComputedNode`): The node to read, written as `p.node_name` (NSE-captured).

- **which_log** (`String`): A regex pattern matching a specific build log filename.


## Returns

The deserialized artifact value, wrapped with diagnostics.

## See Also

[build_log](build_log.html), [list_logs](list_logs.html), [read_node](read_node.html)

