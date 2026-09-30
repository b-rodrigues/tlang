# write_csv

Write CSV file

Writes a DataFrame to a CSV file. Returns a FileError value when the file cannot be written.

## Parameters

- **df** (`DataFrame`): The data to write.

- **path** (`String`): The output path.

- **separator** (`String`): (Optional) Field separator (default ",").


## Returns



## Examples

```t
write_csv(df, "output.csv")
```

## See Also

[read_csv](read_csv.html)

