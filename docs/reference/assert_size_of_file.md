# assert_size_of_file

Assert File Size

Checks that a regular file exists and has the expected size in bytes.

## Parameters

- **path** (`String`): The file path to check.

- **size** (`Int`): The expected size in bytes.

- **message** (`String`): (Optional) Custom assertion message.


## Returns

True if the file exists and has the expected size.

## Examples

```t
assert_size_of_file("output.csv", 128)
assert_size_of_file("report.html", 0, "report should be empty")
```

## See Also

[assert_file_exists](assert_file_exists.html)

