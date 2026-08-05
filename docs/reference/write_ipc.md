# write_ipc

Write Arrow IPC file

Writes a DataFrame to an Apache Arrow IPC (Feather v2) file.  IPC is the fastest format to read and write (no compression), ideal for pipeline intermediates and cross-runtime exchange. For compressed, long-term storage of large datasets, use write_parquet instead.

## Parameters

- **df** (`DataFrame`): The DataFrame to write.

- **path** (`String`): The output file path.


## Returns



## Examples

```t
write_ipc(df, "data.arrow")
```

## See Also

[read_ipc](read_ipc.html)

