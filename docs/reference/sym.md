# sym

Convert a string to a Symbol

Creates a Symbol from a string so it can be injected into quoted code with `!!`. Existing Symbol values pass through unchanged.

## Parameters

- **x** (`String | Symbol`): The name to convert.


## Returns

The resulting symbol.

## Examples

```t
sym("mpg")
expr(select(df, !!sym("mpg")))
```
