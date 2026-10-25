# inspect_node

Inspect Pipeline Node Metadata

Returns a dictionary with metadata about a computed node, including its name, runtime, artifact path, serializer, class, dependencies, and warnings. The `warnings` key contains a structured list of warning records, each with `source` ("own" or the ancestor node name) and `message`. 

Behaviour change: a failed node used to return a TypeError. Code that tested failure with `is_error(inspect_node(x))` must test `inspect_node(x).status == "Errored"` instead. 

A computed node and a failed node return the same ten keys, so one schema covers both cases: 

- `status` is "Built" for a computed node and "Errored" for a failed one. 
- `error_code` and `error_message` describe the failure. Both are NA for a computed node. 
- `class` is the node class for a computed node and "Error" for a failed one. 
- A failed node has no artifact, so `runtime`, `path` and `serializer` are NA, and `dependencies` and `warnings` are empty lists.

## Parameters

- **node** (`ComputedNode`): A computed node value (e.g. from a built pipeline).


## Returns

A dictionary with keys = name, runtime, path, serializer, class, dependencies, warnings, status, error_code, error_message.

## See Also

[warning_msg](warning_msg.html), [rebuild_node](rebuild_node.html), [read_node](read_node.html)

