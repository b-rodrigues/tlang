# expect_column_types

DataFrame column types assertion

Passes if the specified DataFrame columns match the expected type strings.

## Parameters

- **df** (`DataFrame`): The DataFrame to check.

- **expected_types** (`Dict`): | List Column name -> expected type string map.


## Returns

`Expect_pass` when types match; `Expect_hold` on NA; `Expect_stop` on mismatch.

## Examples

```t
assert(expect_column_types(df, [id: "Int", name = "String"]))
```

## See Also

[expect_type](expect_type.html), [expect_colnames](expect_colnames.html)

