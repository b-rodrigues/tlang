# to_integer

Convert to Integer

Coerces a value to an integer robustly. Handles strings with spaces, percentages, commas, and recognizes 'TRUE'/'FALSE'.

## Parameters

- **x** (`Bool | Int | Float | String | List | Vector`): The value to convert.


## Returns

The converted integer.

## Examples

```t
to_integer("12 300")
to_integer("TRUE")
to_integer(3.14)
```

