# expect_table_equal

DataFrame table equality assertion

Passes if two DataFrames have equal dimensions, column names, and matching row contents.

## Parameters

- **df1** (`DataFrame`): First DataFrame.

- **df2** (`DataFrame`): Second DataFrame.

- **ignore_row_order** (`Bool`): = true Ignore row ordering during comparison.


## Returns

`Expect_pass` when tables match; `Expect_hold` on NA; `Expect_stop` on mismatch.

## Examples

```t
assert(expect_table_equal(df1, df2))
```

## See Also

[expect_colnames](expect_colnames.html), [expect_equal](expect_equal.html)

