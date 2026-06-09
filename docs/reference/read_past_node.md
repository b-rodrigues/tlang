# read_past_node

Read Pipeline Node from a Past Build Run

Reads and returns the contents of a pipeline node from a historical build log, identified by `which_log`. Unlike `read_node`, this works without the pipeline being in scope — the node name is captured via NSE from the `p.node_name` syntax.

## Parameters

- **node** (`ComputedNode`): The node to read, written as `p.node_name` (NSE-captured).
- **which_log** (`String`, required): A regex pattern matching a specific build log filename.

## Returns

The deserialized artifact value, wrapped with diagnostics.

## Examples

```t
# Read a node from a specific past build run
read_past_node(base_p.raw, which_log = "qcfs")

# Use list_logs() to find the right log pattern
list_logs()
#   filename                           
#   build_log_20260609_190157_qcfs71...
#   build_log_20260609_192734_alnsv7...
```

## See Also

[read_node](read_node.html), [list_logs](list_logs.html), [build_log](build_log.html)
