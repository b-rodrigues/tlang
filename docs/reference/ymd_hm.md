# ymd_hm

Parse datetimes with minute precision

Parses strings to Datetime values, reading year through minute. Vectorized over vectors. Unparseable inputs become NA.

## Parameters

- **value** (`String | Vector`): The datetime string(s) to parse.

- **tz** (`String`): (Optional) Timezone label.


## Returns

The parsed datetime(s).

## Examples

```t
ymd_hm("2024-01-15 10:30")
```

