# group_by

Group by columns

Groups a DataFrame by one or more columns for subsequent aggregation.

## Parameters

- **df** (`DataFrame`): The input DataFrame.
- **...** (`Symbol`): Variable number of grouping columns.

## Returns

The grouped DataFrame.

## Examples

```t
group_by(mtcars, $cyl)
group_by(mtcars, $cyl, $gear)
```

## See Also

[ungroup](ungroup.md), [summarize](summarize.md)

