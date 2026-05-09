# assert_dir_exists

Assert Directory Exists

Checks that a directory exists at the given path.

## Parameters

- **path** (`String`): The directory path to check.

- **message** (`String`): (Optional) Custom assertion message.


## Returns

True if the directory exists.

## Examples

```t
assert_dir_exists("results")
assert_dir_exists("artifacts", "artifact directory was not created")
```

## See Also

[dir_exists](dir_exists.html), [assert](assert.html)

