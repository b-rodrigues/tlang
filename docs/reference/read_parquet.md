# read_parquet

Read Parquet file

Reads a DataFrame from a Parquet file using the native parquet-glib reader.  Prefer Parquet for compressed, long-term storage of large datasets or when sharing data with external analytics tooling. For the fastest possible round trip (no compression), use read_ipc instead.

## Parameters

- **path** (`String`): Path or URL to the Parquet file.


## Returns

The loaded data.

## Examples

```t
df = read_parquet("data.parquet")
```

## See Also

[read_ipc](read_ipc.html), [read_csv](read_csv.html)

