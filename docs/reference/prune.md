# prune

Prune Pipeline Leaf Nodes

Removes all leaf nodes — nodes that have no downstream dependents (nothing depends on them). This is useful for cleaning up intermediate pipelines after `filter_node` or `difference` operations.

## Parameters

- **p** (`Pipeline`): The pipeline to prune.


## Returns

A new pipeline with leaf nodes removed.

## Examples

```t
p |> difference(p_remove) |> prune
```

## See Also

[difference](difference.html), [filter_node](filter_node.html)

