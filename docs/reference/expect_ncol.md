# expect_ncol

DataFrame column count assertion

Passes if the DataFrame has exactly `n` columns.

## Parameters

- **df** (`DataFrame`): The DataFrame to check.

- **n** (`Int`): Expected column count.


## Returns

`Expect_pass` when column count matches; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.

## Examples

```t
assert(expect_ncol(to_dataframe([x: [1], y = [2]]), 2))
```

## See Also

[expect_length](expect_length.html), [expect_colnames](expect_colnames.html), [expect_nrow](expect_nrow.html)

