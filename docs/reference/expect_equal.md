# expect_equal

Compare two values for testing

Compares `actual` against `expected` and returns a testcraft Expect value (`Expect_pass`, `Expect_stop`, or `Expect_hold`) describing the outcome. Designed to be used with `assert()`: `assert(expect_equal(a, b))`.

## Parameters

- **actual** (`Any`): The computed value to check.

- **expected** (`Any`): The value `actual` is expected to equal.

- **tolerance** (`Float`): = 1e-9 Absolute tolerance used for Float comparisons.


## Returns

A `VExpect` value: passing, stopping, or holding (on NA).

## Examples

```t
expect_equal(1, 1)
assert(expect_equal(0.1 + 0.2, 0.3, tolerance = 1e-9))
```

## See Also

[assert](assert.html), [expect_msg](expect_msg.html), [expect_fail](expect_fail.html), [expect_pass](expect_pass.html)

