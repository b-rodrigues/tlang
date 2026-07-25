# expect_between

Closed range numerical bounds assertion

Passes if the numeric value or vector elements fall inside [min, max].

## Parameters

- **actual** (`Int`): | Float | Vector The numeric value or vector to check.

- **min** (`Int`): | Float Lower bound (inclusive).

- **max** (`Int`): | Float Upper bound (inclusive).


## Returns

`Expect_pass` when within bounds; `Expect_hold` on NA; `Expect_stop` if out of bounds.

## Examples

```t
assert(expect_between(25.0, 10.0, 50.0))
```

## See Also

[expect_lt](expect_lt.html), [expect_gt](expect_gt.html)

