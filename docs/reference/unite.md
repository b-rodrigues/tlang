# unite

Combine multiple columns into one character column

unite() is a convenience function that pastes together multiple columns into a single character column.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **col** (`String`): The name of the new column to create.

- **...** (`Symbol`): The columns to combine (use $col syntax).

- **sep** (`String`): (Optional) Separator to use between values.

- **remove** (`Bool`): (Optional) If true, remove the input columns from the result.

- **na_rm** (`Bool`): (Optional) If true, missing values will be removed prior to uniting.


## Returns

The united DataFrame.

## Examples

```t
unite(df, "full_name", $first_name, $last_name, sep = " ")
```

