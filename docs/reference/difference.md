# difference

Difference of Two Pipelines

Removes from `p1` all nodes whose names appear in `p2`. Nodes in `p2` that are not present in `p1` are silently ignored. No DAG validity check is performed after the removal.

## Parameters

- **p1** (`Pipeline`): The pipeline to remove nodes from.
- **p2** (`Pipeline`): The pipeline whose node names determine what to remove.

## Returns:

Returns: A new pipeline with the specified nodes removed.

## Examples

```t
p_full |> difference(p_to_remove)
```

## See Also

[patch](patch.html), [intersect](intersect.html), [union](union.html)

