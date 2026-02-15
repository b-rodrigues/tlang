# summarize

Summarize data

Aggregates a DataFrame to a single row (or one row per group).

## Parameters

- **df** (`DataFrame`): The input DataFrame.
- **...** (`KeywordArgs`): Aggregations as name = expression pairs.

## Returns

The summarized DataFrame.

## Examples

```t
summarize(mtcars, $mean_mpg = mean($mpg))
summarize(group_by(mtcars, $cyl), $mean_hp = mean($hp))
```

## See Also

[mutate](mutate.md), [group_by](group_by.md)

