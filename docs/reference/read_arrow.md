# read_arrow

Read Arrow IPC file

Reads a DataFrame from an Apache Arrow IPC (Feather v2) file.

## Parameters

- **path** (`String`): The path to the Arrow file.


## Returns

The loaded DataFrame.

## Examples

```t
df = read_arrow("data.arrow")
```

## See Also

[write_arrow](write_arrow.html)

