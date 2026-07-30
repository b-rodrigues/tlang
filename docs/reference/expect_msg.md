# expect_msg

Get the diagnostic message from a failing Expect value

Returns the `Stop`/`Hold` message carried by a failing `VExpect` value. If `x` passed (`Expect_pass`), there is no message to extract and a `VError` is returned instead.

## Parameters

- **x** (`Expect`): The Expect value to inspect.


## Returns

The diagnostic message, or an error if `x` is not a failure.

## Examples

```t
expect_msg(expect_equal(1, 2))
```

## See Also

[expect_fail](expect_fail.html), [expect_pass](expect_pass.html), [expect_equal](expect_equal.html)

