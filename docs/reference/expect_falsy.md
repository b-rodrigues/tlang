# expect_falsy

Loose falsiness assertion

Passes if `x` is falsy per `is_truthy` (`0`, `false`, `VNullNode`, empty containers, etc.). NA produces `Expect_hold`.

## Parameters

- **x** (`Any`): The value to check.


## Returns

`Expect_pass` when `x` is falsy; `Expect_hold` on NA; `Expect_stop` on errors or truthy values.

## Examples

```t
assert(expect_falsy(0))
assert(expect_falsy(false))
```

## See Also

[expect_truthy](expect_truthy.html), [expect_false](expect_false.html), [expect_true](expect_true.html)

