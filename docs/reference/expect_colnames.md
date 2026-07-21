# expect_colnames

DataFrame column names assertion

Passes if the DataFrame column names match the given list of strings exactly (order-sensitive).

## Parameters

- **df** (`DataFrame`): The DataFrame to check.

- **names** (`List`): | Vector A list or vector of expected column name strings.


## Returns

`Expect_pass` when names match; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.

## Examples

```t
assert(expect_colnames(to_dataframe([x: [1], y = [2]]), ["x", "y"]))
```

## See Also

[expect_fields](expect_fields.html), [expect_ncol](expect_ncol.html), [expect_nrow](expect_nrow.html)

