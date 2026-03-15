# read_parquet

Read Parquet file

Reads a DataFrame from a Parquet file using the native parquet-glib reader.

## Parameters

- **path** (`String`): Path or URL to the Parquet file.


## Returns

The loaded data.

## Examples

```t
df = read_parquet("data.parquet")
```

## See Also

[read_csv](read_csv.html), [read_arrow](read_arrow.html)
