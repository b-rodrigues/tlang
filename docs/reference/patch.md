# patch

Patch a Pipeline

Updates nodes in `p1` with definitions from `p2`, but only for nodes that already exist in `p1`. New nodes from `p2` are not added. Useful for overriding node configurations without accidentally importing stray nodes.

## Parameters

- **p1** (`Pipeline`): The base pipeline.
- **p2** (`Pipeline`): The pipeline providing updated node definitions.

## Returns:

Returns: A new pipeline with matching nodes updated from `p2`.

## Examples

```t
p_prod |> patch(p_staging_overrides)
```

## See Also

[intersect](intersect.md), [difference](difference.md), [union](union.md)

