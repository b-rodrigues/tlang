# count

Count rows by group

Counts rows in a DataFrame, optionally by selected columns or existing group keys.

## Parameters

- **df** (`DataFrame`): The input data frame.

- **...** (`Column`): Columns to group by (bare names or $col references).

- **name** (`String`): = "n" Name for the count column.


## Returns

A DataFrame with one row per group and a count column.

## Examples

```t
count(df)
count(df, $species)
count(df, $species, $year, name = "freq")
```

