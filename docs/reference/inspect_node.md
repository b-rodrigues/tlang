# inspect_node

Inspect Pipeline Node Metadata

Returns a dictionary with metadata about a computed node, including its name, runtime, artifact path, serializer, class, dependencies, and warnings. The `warnings` key contains a structured list of warning records, each with `source` ("own" or the ancestor node name) and `message`.

## Parameters

- **node** (`ComputedNode`): A computed node value (e.g. from a built pipeline).


## Returns

A dictionary with keys = name, runtime, path, serializer, class, dependencies, warnings.

## See Also

[warning_msg](warning_msg.html), [rebuild_node](rebuild_node.html), [read_node](read_node.html)

