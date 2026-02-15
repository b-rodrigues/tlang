# assert

Assert Condition

Checks if a condition is true, raising an error if false.

## Parameters

- **condition** (`Bool`): The condition to check.
- **message** (`String`): (Optional) Custom error message.

## Returns

True if successful.

## Examples

```t
assert(1 == 1)
assert(x > 0, "x must be positive")
```

## See Also

[is_error](is_error.md), [error](error.md)

