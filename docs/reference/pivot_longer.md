# pivot_longer

Pivot longer

Lengthens data, increasing the number of rows and decreasing the number of columns.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **...** (`Symbol`): The columns to pivot into longer format (use $col syntax).

- **names_to** (`String`): (Optional) The name of the new column to hold the column names. Defaults to "name".

- **values_to** (`String`): (Optional) The name of the new column to hold the values. Defaults to "value".


## Returns

The pivoted DataFrame.

## Examples

```t
pivot_longer(df, $A, $B, names_to = "name", values_to = "value")
```

