# expect_no_na

Absence of NA values assertion

Passes if the actual value, Vector, List, or DataFrame (optional column) contains zero NA values.

## Parameters

- **actual** (`Any`): The value, container, or DataFrame to check.

- **col** (`String`): (Optional) Column name when checking a DataFrame.


## Returns

`Expect_pass` when no NA values exist; `Expect_stop` if NA values are found.

## Examples

```t
assert(expect_no_na([1, 2, 3]))
assert(expect_no_na(df, "val"))
```

## See Also

[expect_true](expect_true.html), [expect_type](expect_type.html)

