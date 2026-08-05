# read_ipc

Read an Arrow IPC (Feather) file

Loads a DataFrame from an Arrow IPC file (also known as Feather v2) on disk.  IPC is the fastest format to read and write (no compression), ideal for pipeline intermediates and cross-runtime exchange. For compressed, long-term storage of large datasets, use read_parquet instead.

## Parameters

- **path** (`String`): The file path to the Arrow IPC file.


## Returns

The loaded DataFrame.

## Examples

```t
df = read_ipc("data.arrow")
```

## See Also

[read_csv](read_csv.html), [write_ipc](write_ipc.html)

