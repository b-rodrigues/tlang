# sprintf

Format a string

Formats a string using C-style format specifiers. Supports %s (string), %d (integer), %f (float), and %% (literal %).

## Parameters

- **fmt** (`String`): The format string.
- **...** (`Any`): Values to substitute in the format string.

## Returns

The formatted string.

## Examples

```t
sprintf("Hello, %s!", "world")
-- Returns: "Hello, world!"
sprintf("Value: %d", 42)
-- Returns: "Value: 42"
```

