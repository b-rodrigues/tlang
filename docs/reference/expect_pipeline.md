# expect_pipeline

Pipeline assertion

Passes if `x` is a Pipeline value.

## Parameters

- **x** (`Any`): The value to check.


## Returns

`Expect_pass` if a Pipeline; `Expect_stop` otherwise.

## Examples

```t
assert(expect_pipeline(p))
```

