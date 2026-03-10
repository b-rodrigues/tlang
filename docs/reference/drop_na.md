# drop_na

Remove rows with missing values

drop_na() removes rows from a DataFrame where specified columns have missing values.

## Parameters

- **df** (`DataFrame`): The DataFrame.

- **...** (`Symbol`): (Optional) Columns to check for missing values (use $col syntax).


## Returns

The DataFrame with NA rows removed.

## Examples

```t
drop_na(df)
drop_na(df, $age, $score)
```

