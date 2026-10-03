# ydm

Parse year-day-month dates

Parses strings in YDM order to Date values. Vectorized over vectors. Unparseable inputs become NA.

## Parameters

- **value** (`String | Vector`): The date string(s) to parse.


## Returns

The parsed date(s).

## Examples

```t
ydm("2024-15-01")
```

