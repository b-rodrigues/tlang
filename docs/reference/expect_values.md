# expect_values

DataFrame column allowed values assertion

Passes if all cell values in a DataFrame column belong to an allowed set of values.

## Parameters

- **df** (`DataFrame`): The DataFrame to inspect.

- **col** (`String`): Column name to check.

- **allowed_values** (`List`): | Vector Set of allowed values.


## Returns

`Expect_pass` when all values are allowed; `Expect_hold` on NA; `Expect_stop` on disallowed values.

## Examples

```t
assert(expect_values(df, "status", ["PENDING", "APPROVED"]))
```

## See Also

[expect_range](expect_range.html), [expect_in](expect_in.html)

