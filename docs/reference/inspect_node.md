# inspect_node

Inspect Pipeline Node Metadata

Returns a dictionary with metadata about a computed node, including its name, runtime, artifact path, serializer, class, and dependencies.

## Parameters

- **node** (`ComputedNode`): A computed node value (e.g. from a built pipeline).


## Returns

A dictionary with keys = name, runtime, path, serializer, class, dependencies.

## See Also

[rebuild_node](rebuild_node.html), [read_node](read_node.html)

