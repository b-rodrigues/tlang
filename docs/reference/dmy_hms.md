# dmy_hms

Parse day-first datetimes with second precision

Parses DMY-ordered strings to Datetime values. Vectorized over vectors. Unparseable inputs become NA.

## Parameters

- **value** (`String`): | Vector The datetime string(s) to parse.

- **tz** (`String`): (Optional) Timezone label.


## Returns

| Vector The parsed datetime(s).

## Examples

```t
dmy_hms("15-01-2024 10:30:45")
```

