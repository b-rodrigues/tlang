# expect_in

Set membership assertion

Passes if `x` (or every element of a Vector/List `x`) is present in `values`. Checks each element of collections individually.

## Parameters

- **x** (`Any`): A scalar value, Vector, or List to look for.

- **values** (`Vector`): | List The haystack collection to search in.

- **tolerance** (`Float`): = 1e-9 Absolute tolerance used for Float comparisons.


## Returns

`Expect_pass` when all elements are found; `Expect_hold` on NA; `Expect_stop` on errors or mismatch.

## Examples

```t
assert(expect_in(3, [1, 2, 3, 4, 5]))
assert(expect_in(0.1 + 0.2, [0.3], tolerance = 1e-9))
```

## See Also

[expect_equal](expect_equal.html), [expect_fields](expect_fields.html)

