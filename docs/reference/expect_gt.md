# expect_gt

Numeric greater-than assertion

Passes if `a > b` for numeric arguments (Int or Float).

## Parameters

- **a** (`Int`): | Float The left-hand numeric value.

- **b** (`Int`): | Float The right-hand numeric value.


## Returns

`Expect_pass` when `a > b`, `Expect_stop` otherwise.

## Examples

```t
assert(expect_gt(2, 1))
```

## See Also

[expect_equal](expect_equal.html), [expect_gte](expect_gte.html), [expect_lte](expect_lte.html), [expect_lt](expect_lt.html)

