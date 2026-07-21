# expect_false

Strict boolean false assertion

Passes only if `x` is `VBool false`. For a looser falsiness check, use `expect_falsy` instead.

## Parameters

- **x** (`Any`): The value to check.


## Returns

`Expect_pass` only when `x` is `false`; `Expect_hold` on NA; `Expect_stop` on errors or non-false values.

## Examples

```t
assert(expect_false(false))
assert(expect_false(2 < 1))
```

## See Also

[expect_falsy](expect_falsy.html), [expect_truthy](expect_truthy.html), [expect_true](expect_true.html)

