# pivot_wider

Pivot wider

Widens data, increasing the number of columns and decreasing the number of rows.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **names_from** (`Symbol`): The column whose values become output column names (use $col syntax).

- **values_from** (`Symbol`): The column whose values fill the new columns (use $col syntax).


## Returns

The pivoted DataFrame.

## Examples

```t
pivot_wider(df, names_from = $name, values_from = $value)
```

