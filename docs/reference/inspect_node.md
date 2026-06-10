# inspect_node

Inspect Pipeline Node Metadata

Returns a dictionary with metadata about a computed node, including its name, runtime, artifact path, serializer, class, dependencies, and any captured warnings (both own and inherited from upstream ancestors).

## Parameters

- **node** (`ComputedNode`): A computed node value (e.g. from a built pipeline).


## Returns

A dictionary with keys = name, runtime, path, serializer, class, dependencies, warnings.

The `warnings` key contains a list of structured warning records, each with:

- `source` (`String`): `"own"` for warnings originating from this node, or the name of the ancestor node for inherited upstream warnings.
- `message` (`String`): The human-readable warning message.

```t
inspect_node(p.count)
-- Returns:
-- dict
--   ├── name: "count"
--   ├── runtime: "T"
--   ├── path: "/nix/store/...-pipeline_output/count/artifact"
--   ├── serializer: "default"
--   ├── class: "Int"
--   ├── dependencies: ["filtered"]
--   └── warnings: [
--       ├── dict
--       │   ├── source: "filtered"
--       │   └── message: "filter() excluded 1 row because the predicate evaluated to NA"
--       ]
```

## See Also

[rebuild_node](rebuild_node.html), [read_node](read_node.html), [warning_msg](warning_msg.html)

