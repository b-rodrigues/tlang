# intersect

Intersection of Two Pipelines

Returns a new pipeline retaining only the nodes present by name in both pipelines. Definitions are taken from `p1`.

## Parameters

- **p1** (`Pipeline`): The pipeline whose definitions are kept.
- **p2** (`Pipeline`): The pipeline used to determine which nodes to retain.

## Returns:

Returns: A new pipeline with only the shared nodes (p1 definitions).

## Examples

```t
p_full |> intersect(p_subset)
```

## See Also

[patch](patch.html), [difference](difference.html), [union](union.html)

