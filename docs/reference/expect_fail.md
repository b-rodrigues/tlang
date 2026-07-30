# expect_fail

Check whether an Expect value failed

Returns `true` if `x` is a `VExpect Expect_stop` or `VExpect Expect_hold` value (i.e. an `expect_*` comparison that did not pass). Useful for explicit checks alongside `assert()`.

## Parameters

- **x** (`Expect`): The Expect value to inspect.


## Returns

True if `x` is a stopping or holding Expect value.

## Examples

```t
assert(expect_fail(expect_equal(1, 2)))
```

## See Also

[expect_msg](expect_msg.html), [expect_pass](expect_pass.html), [expect_equal](expect_equal.html)

