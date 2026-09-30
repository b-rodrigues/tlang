# mdy

Parse month-day-year dates

Parses strings in MDY order to Date values. Vectorized over vectors. Unparseable inputs become NA.

## Parameters

- **value** (`String`): | Vector The date string(s) to parse.


## Returns

| Vector The parsed date(s).

## Examples

```t
mdy("01-15-2024")
*)
```

