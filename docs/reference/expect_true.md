# expect_true

Strict boolean true assertion

Passes only if `x` is `VBool true`. For a looser truthiness check, use `expect_truthy` instead.

## Parameters

- **x** (`Any`): The value to check.


## Returns

`Expect_pass` only when `x` is `true`; `Expect_hold` on NA; `Expect_stop` on errors or non-true values.

## Examples

```t
assert(expect_true(true))
assert(expect_true(1 < 2))
```

## See Also

[expect_falsy](expect_falsy.html), [expect_truthy](expect_truthy.html), [expect_false](expect_false.html)

