# debug_node

Interactively Debug a Pipeline Node

Spawns an interactive debug subshell (Python, R, or Julia REPL) for the specified ComputedNode. The REPL is pre-configured with the node's environment variables and package environment, and displays instructions for loading upstream dependency artifacts.

## Parameters

- **node** (`ComputedNode`): The ComputedNode object to debug (e.g. `p.node_name`).


## Returns

(Generates an interactive console session).

## Examples

```t
debug_node(p.etl_clean)
```

