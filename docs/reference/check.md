# check

Inline assertion wrapper

Evaluates `assert(val)`, prints `true` on success, and preserves the original `VError` on failure. Suitable for use inside pipeline node commands where the result must be visible in logs.

## Parameters

- **val** (`Any`): The value to assert.


## Returns

`true` on success; the original `VError` on failure.

## Examples

```t
check(expect_equal(1 + 1, 2))
```

## See Also

[expect_equal](expect_equal.html), [assert](assert.html)

