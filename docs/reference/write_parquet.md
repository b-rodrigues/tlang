# write_parquet

Write Parquet file

Writes a DataFrame to a Parquet file using the native parquet-glib writer.

## Parameters

- **df** (`DataFrame`): The DataFrame to write.

- **path** (`String`): The output file path.


## Returns



## Examples

```t
write_parquet(df, "data.parquet")
```

## See Also

[write_arrow](write_arrow.html), [read_parquet](read_parquet.html)

