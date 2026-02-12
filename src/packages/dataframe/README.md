# dataframe

DataFrame creation and introspection.

## Functions

| Function | Description |
|----------|-------------|
| `read_csv(path)` | Read a CSV file into a DataFrame |
| `write_csv(df, path)` | Write a DataFrame to a CSV file |
| `colnames(df)` | Return column names |
| `nrow(df)` | Return number of rows |
| `ncol(df)` | Return number of columns |
| `clean_colnames(df)` | Clean column names (snake_case) |
| `glimpse(df)` | Compact summary of a DataFrame |

## Named Arguments

`read_csv` supports:
- `separator = ","` — field delimiter (single character)
- `skip_header = false` — if true, auto-generate column names V1, V2, ...
- `skip_lines = 0` — skip first N lines
- `clean_colnames = false` — auto-clean column names

## Examples

```t
df = read_csv("data.csv")
colnames(df)          -- ["col1", "col2", ...]
nrow(df)              -- number of rows
glimpse(df)           -- compact summary
write_csv(df, "output.csv")
```

## Status

Built-in package — included with T by default.
