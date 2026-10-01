# mdy_hms

Parse month-first datetimes with second precision

Parses MDY-ordered strings to Datetime values. Vectorized over vectors. Unparseable inputs become NA.

## Parameters

- **value** (`String`): | Vector The datetime string(s) to parse.

- **tz** (`String`): (Optional) Timezone label.


## Returns

| Vector The parsed datetime(s).

## Examples

```t
mdy_hms("01-15-2024 10:30:45")
```

