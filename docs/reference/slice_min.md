# slice_min

Keep rows with the smallest values

Returns the rows with the lowest values in an ordering column.

## Parameters

- **df** (`DataFrame`): The input data frame.

- **order_by** (`Column`): The column to order by.

- **n** (`Int`): = 1 Number of rows to return.


## Returns

A DataFrame with the bottom n rows by the ordering column.

## Examples

```t
slice_min(df, $score)
slice_min(df, $score, n = 5)
```

