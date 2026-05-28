# pipeline_diff

Compare Two Pipeline Structures

Compares two `Pipeline` values and returns a structured diff describing
which nodes were added, removed, changed, or had their edges rewired.

Unlike `node_diff`, which compares node *artifacts* (the values they
produce), `pipeline_diff` compares pipeline *structure* — the nodes,
their metadata, and their dependency edges.

## Signature

```t
pipeline_diff(p_a :: Pipeline, p_b :: Pipeline) :: Dict
```

## Parameters

- **p_a** (`Pipeline`): The "before" pipeline.
- **p_b** (`Pipeline`): The "after" pipeline.

## Returns

`Dict`: A pipeline diff dictionary with the following fields:

| Field | Type | Description |
|---|---|---|
| `kind` | `String` | Always `"pipeline_diff"` |
| `identical` | `Bool` | `true` if no structural differences were found |
| `added_nodes` | `List[String]` | Node names present in `p_b` but not `p_a` |
| `removed_nodes` | `List[String]` | Node names present in `p_a` but not `p_b` |
| `changed_nodes` | `List[String]` | Shared nodes whose metadata changed |
| `rewired_edges` | `List[Dict]` | Edges that changed between the two pipelines |
| `frame_a` | `DataFrame` | `pipeline_to_frame(p_a)` |
| `frame_b` | `DataFrame` | `pipeline_to_frame(p_b)` |

## Examples

```t
-- Compare two versions of a pipeline
d = pipeline_diff(p_v1, p_v2)

-- Check if anything changed
if (d.identical) {
  print("Pipelines are identical")
} else {
  print("Added nodes: " ++ to_string(d.added_nodes))
  print("Removed nodes: " ++ to_string(d.removed_nodes))
}
```

## See Also

- `node_diff` — compare node artifacts across builds
- `pipeline_to_frame` — convert pipeline metadata to a DataFrame
