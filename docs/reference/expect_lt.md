# expect_lt

Numeric less-than assertion

Passes if `a < b` for numeric arguments (Int or Float). Returns `Expect_hold` when either argument is NA; `Expect_stop` on errors.

## Parameters

- **a** (`Int`): | Float The left-hand numeric value.

- **b** (`Int`): | Float The right-hand numeric value.


## Returns

`Expect_pass` when `a < b`, `Expect_stop` otherwise.

## Examples

```t
assert(expect_lt(1, 2))
assert(expect_lt(1.5, 2.5))
```

## See Also

[expect_equal](expect_equal.html), [expect_gte](expect_gte.html), [expect_gt](expect_gt.html), [expect_lte](expect_lte.html)

