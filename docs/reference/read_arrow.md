# read_arrow

Read an Arrow IPC (Feather) file

Loads a DataFrame from an Arrow IPC file (also known as Feather v2) on disk.

## Parameters

- **path** (`String`): The file path to the Arrow IPC file.


## Returns

The loaded DataFrame.

## Examples

```t
df = read_arrow("data.arrow")
```

## See Also

[read_csv](read_csv.html), [write_arrow](write_arrow.html)

