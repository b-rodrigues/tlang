# arrange

Arrange rows

Sorts a DataFrame by a column. Use "desc" for descending order.

## Parameters

- **df** (`DataFrame`): The input DataFrame.
- **col** (`Symbol`): The column to sort by.
- **direction** (`String`): (Optional) "asc" (default) or "desc".

## Returns

The sorted DataFrame.

## Examples

```t
arrange(mtcars, $mpg)
arrange(mtcars, $mpg, "desc")
```

## See Also

[group_by](group_by.md), [filter](filter.md)

