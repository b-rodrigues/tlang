# error

Raise Error

Raises a runtime error with a message and optional code.

## Parameters

- **message_or_code** (`String`): The error message (if 1 argument) or error code (if 2 arguments).

- **message** (`String`): (Optional) The error message if a code was provided as the first argument.


## Returns



## Examples

```t
error("Invalid input")
error("ValueError", "Must be positive")
```

## See Also

[is_error](is_error.html), [assert](assert.html)

