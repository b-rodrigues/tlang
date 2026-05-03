# dataframe

DataFrame creation and introspection.

## Functions

| Function | Description |
|----------|-------------|
| `dataframe(data)` | Create a DataFrame from rows or columns |
| `read_csv(path)` | Read CSV file |
| `read_parquet(path)` | Read Parquet file |
| `read_arrow(path)` | Read Arrow IPC file |
| `write_csv(df, path)` | Write CSV file |
| `write_arrow(df, path)` | Write Arrow IPC file |
| `nrow(df)` / `ncol(df)` | Get dimensions |
| `colnames(df)` | Get column names |
| `clean_colnames(df)` | Normalize column names |
| `glimpse(df)` | Summarize structure |
| `pull(df, col)` | Extract column as vector |
| `to_array(df)` | Convert to NDArray |

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
