# select

Select columns

Selects specific columns from a DataFrame.

## Parameters

- **df** (`DataFrame`): The input DataFrame.
- **...** (`Symbol`): Variable number of column names (e.g., $col1, $col2).

## Returns

The DataFrame with selected columns.

## Examples

```t
select(mtcars, $mpg, $wt)
```

## See Also

[mutate](mutate.md), [filter](filter.md)

