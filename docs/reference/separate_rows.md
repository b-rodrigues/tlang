# separate_rows

Split delimited values into rows

Expands delimited string values into multiple rows while repeating the remaining columns.

## Parameters

- **df** (`DataFrame`): The input data frame.

- **col** (`Column`): The column to split (bare name or $col reference).

- **sep** (`String`): = "[^A-Za-z0-9]+" Regular expression separator pattern.


## Returns

A DataFrame with the column values split across rows.

## Examples

```t
separate_rows(df, $items)
separate_rows(df, $codes, sep = ",")
```

