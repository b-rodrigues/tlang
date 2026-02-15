# read_csv

Read CSV file

Reads a CSV file into a DataFrame.

## Parameters

- **path** (`String`): Path or URL to the CSV file.
- **separator** (`String`): (Optional) Field separator (default ",").
- **skip_header** (`Bool`): (Optional) Skip proper header parsing? (default false).
- **skip_lines** (`Int`): (Optional) Number of lines to skip at start.
- **clean_colnames** (`Bool`): (Optional) Clean column names? (default false).

## Returns

The loaded data.

## Examples

```t
df = read_csv("data.csv")
df = read_csv("data.csv", separator: ";")
```

## See Also

[write_csv](write_csv.md)

