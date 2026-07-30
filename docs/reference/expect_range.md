# expect_range

DataFrame numeric column closed range bounds assertion

Passes if all non-NA cell values in a numeric DataFrame column fall within [min, max].

## Parameters

- **df** (`DataFrame`): The DataFrame to inspect.

- **col** (`String`): Column name to check.

- **min** (`Int`): | Float Lower bound (inclusive).

- **max** (`Int`): | Float Upper bound (inclusive).


## Returns

`Expect_pass` when within bounds; `Expect_hold` on NA; `Expect_stop` if out of bounds.

## Examples

```t
assert(expect_range(df, "age", 0, 120))
```

## See Also

[expect_values](expect_values.html), [expect_between](expect_between.html)

