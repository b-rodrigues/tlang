# write_parquet

Write Parquet file

Writes a DataFrame to a Parquet file using the native parquet-glib writer.  Prefer Parquet for compressed, long-term storage of large datasets or when sharing data with external analytics tooling. For the fastest possible round trip (no compression), use write_ipc instead.

## Parameters

- **df** (`DataFrame`): The DataFrame to write.

- **path** (`String`): The output file path.


## Returns



## Examples

```t
write_parquet(df, "data.parquet")
```

## See Also

[write_ipc](write_ipc.html), [read_parquet](read_parquet.html)

