# expect_error

Error assertion with optional class and message filtering

Passes if `expr` is a `VError`. Optionally verifies the error class string and/or applies a regex pattern match against the error message.

## Parameters

- **expr** (`Any`): The value to check (typically the result of an expression that may error).

- **class** (`String`): = "" Optional error class to match (e.g. `"TypeError"`, `"RuntimeError"`).

- **message** (`String`): = "" Optional regex pattern to match against the error message.


## Returns

`Expect_pass` when all checks pass; `Expect_stop` otherwise.

## Examples

```t
assert(expect_error(error("boom")))
assert(expect_error(error("boom"), class = "GenericError"))
assert(expect_error(error("invalid value"), message = "invalid"))
```

## See Also

[expect_true](expect_true.html), [expect_type](expect_type.html)

