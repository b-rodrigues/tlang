# expect_lte

Numeric less-than-or-equal assertion

Passes if `a <= b` for numeric arguments (Int or Float).

## Parameters

- **a** (`Int`): | Float The left-hand numeric value.

- **b** (`Int`): | Float The right-hand numeric value.


## Returns

`Expect_pass` when `a <= b`, `Expect_stop` otherwise.

## Examples

```t
assert(expect_lte(1, 1))
assert(expect_lte(1, 2))
```

## See Also

[expect_equal](expect_equal.html), [expect_gte](expect_gte.html), [expect_gt](expect_gt.html), [expect_lt](expect_lt.html)

