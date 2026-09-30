# ymd_h

Parse datetimes with hour precision

Parses strings to Datetime values, reading year through hour. Vectorized over vectors. Unparseable inputs become NA.

## Parameters

- **value** (`String`): | Vector The datetime string(s) to parse.

- **tz** (`String`): (Optional) Timezone label.


## Returns

| Vector The parsed datetime(s).

## Examples

```t
ymd_h("2024-01-15 10")
*)
```

