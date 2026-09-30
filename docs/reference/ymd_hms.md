# ymd_hms

Parse datetimes with second precision

Parses strings to Datetime values, reading year through second. Vectorized over vectors. Unparseable inputs become NA.

## Parameters

- **value** (`String`): | Vector The datetime string(s) to parse.

- **tz** (`String`): (Optional) Timezone label.


## Returns

| Vector The parsed datetime(s).

## Examples

```t
ymd_hms("2024-01-15 10:30:45")
*)
```

