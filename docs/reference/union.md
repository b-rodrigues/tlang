# union

Union of Two Pipelines

Merges two pipelines into one. All nodes from both pipelines are included. Errors immediately if any node name exists in both pipelines. Use `rename_node` to resolve collisions before calling `union`.

## Parameters

- **p1** (`Pipeline`): The first pipeline.
- **p2** (`Pipeline`): The second pipeline.

## Returns:

Returns: A new pipeline containing all nodes from both.

## Examples

```t
p_etl |> union(p_model)
```

## See Also

[rename_node](rename_node.html), [patch](patch.html), [intersect](intersect.html), [difference](difference.html)

