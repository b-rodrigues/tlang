# ymd

Parse year-month-day dates

Parses strings in YMD order to Date values. Vectorized over vectors. Unparseable inputs become NA.

## Parameters

- **value** (`String | Vector`): The date string(s) to parse.


## Returns

The parsed date(s).

## Examples

```t
ymd("2024-01-15")
```

