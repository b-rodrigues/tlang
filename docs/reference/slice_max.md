# slice_max

Keep rows with the largest values

Returns the rows with the highest values in an ordering column.

## Parameters

- **df** (`DataFrame`): The input data frame.

- **order_by** (`Column`): The column to order by.

- **n** (`Int`): = 1 Number of rows to return.


## Returns

A DataFrame with the top n rows by the ordering column.

## Examples

```t
slice_max(df, $score)
slice_max(df, $score, n = 5)
```

