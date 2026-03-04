# to_float

Convert to Float

Coerces a value to a float robustly. Handles strings with spaces, percentages, commas, and recognizes 'TRUE'/'FALSE'.

## Parameters

- **x** (`Any`): The value to convert.

## Returns:

Returns: | NA The converted float.

## Examples

```t
to_float("3,14")
to_float("15%")
to_float(42)
```

