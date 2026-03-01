# to_integer

Convert to Integer

Coerces a value to an integer robustly. Handles strings with spaces, percentages, commas, and recognizes 'TRUE'/'FALSE'.

## Parameters

- **x** (`Any`): The value to convert.

## Returns

| NA The converted integer.

## Examples

```t
to_integer("12 300")
to_integer("TRUE")
to_integer(3.14)
```

