# assert_non_empty_file

Assert File Is Non-Empty

Checks that a regular file exists and contains at least one byte.

## Parameters

- **path** (`String`): The file path to check.

- **message** (`String`): (Optional) Custom assertion message.


## Returns

True if the file exists and is non-empty.

## Examples

```t
assert_non_empty_file("output.csv")
assert_non_empty_file("plot.png", "plot was not written")
```

## See Also

[assert_size_of_file](assert_size_of_file.html), [assert_file_exists](assert_file_exists.html)

