# dmy

Parse day-month-year dates

Parses strings in DMY order to Date values. Vectorized over vectors. Unparseable inputs become NA.

## Parameters

- **value** (`String`): | Vector The date string(s) to parse.


## Returns

| Vector The parsed date(s).

## Examples

```t
dmy("15-01-2024")
*)
```

