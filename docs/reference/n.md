# n

Group size aggregation

Returns the number of rows in the current aggregation context. Use this inside `summarize()` to count rows per group.

## Returns

The row count.

## Examples

```t
df |> group_by($species) |> summarize($rows = n())
```

## See Also

[summarize](summarize.html), [count](count.html)
