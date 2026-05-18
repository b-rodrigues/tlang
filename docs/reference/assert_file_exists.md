# assert_file_exists

Assert File Exists

Checks that a regular file exists at the given path.

## Parameters

- **path** (`String`): The file path to check.

- **message** (`String`): (Optional) Custom assertion message.


## Returns

True if the file exists.

## Examples

```t
assert_file_exists("output.csv")
assert_file_exists("report.html", "report generation failed")
```

## See Also

[file_exists](file_exists.html), [assert](assert.html)

