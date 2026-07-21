# expect_truthy

Loose truthiness assertion

Passes if `x` is truthy per `is_truthy` (non-zero numbers, non-empty strings, non-empty containers, etc.).

## Parameters

- **x** (`Any`): The value to check.


## Returns

`Expect_pass` when `x` is truthy; `Expect_hold` on NA; `Expect_stop` on errors or falsy values.

## Examples

```t
assert(expect_truthy(42))
assert(expect_truthy("hello"))
```

## See Also

[expect_falsy](expect_falsy.html), [expect_false](expect_false.html), [expect_true](expect_true.html)

