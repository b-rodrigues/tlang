# read_log

Read Node Build Log

Fetches the Nix build log for a specific node from the last build attempt. Takes the node directly (`p.node_name`), matching `read_node`.

## Parameters

- **node** (`ComputedNode`): The node to inspect, written as `p.node_name`.


## Returns

The build log content.

