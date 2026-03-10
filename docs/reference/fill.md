# fill

Fill missing values

Fills missing values in selected columns using the next or previous entry.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **...** (`Symbol`): Columns to fill (use $col syntax).

- **.direction** (`String`): (Optional) Direction in which to fill missing values.


## Returns

The filled DataFrame.

## Examples

```t
fill(df, $category, .direction = "down")
```

