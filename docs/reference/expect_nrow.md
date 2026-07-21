# expect_nrow

DataFrame row count assertion

Passes if the DataFrame has exactly `n` rows.

## Parameters

- **df** (`DataFrame`): The DataFrame to check.

- **n** (`Int`): Expected row count.


## Returns

`Expect_pass` when row count matches; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.

## Examples

```t
assert(expect_nrow(to_dataframe([x: [1, 2, 3]]), 3))
```

## See Also

[expect_length](expect_length.html), [expect_colnames](expect_colnames.html), [expect_ncol](expect_ncol.html)

