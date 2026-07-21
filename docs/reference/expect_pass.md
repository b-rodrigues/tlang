# expect_pass

Check whether an Expect value passed

Returns `true` if `x` is a `VExpect Expect_pass` value (i.e. an `expect_*` comparison that succeeded). Useful for explicit checks alongside `assert()`.

## Parameters

- **x** (`Expect`): The Expect value to inspect.


## Returns

True if `x` is a passing Expect value.

## Examples

```t
assert(expect_pass(expect_equal(a, b)))
```

## See Also

[expect_msg](expect_msg.html), [expect_fail](expect_fail.html), [expect_equal](expect_equal.html)

