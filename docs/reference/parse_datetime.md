# parse_datetime

Parse datetimes from strings

Parses strings or string vectors into Datetime values using an explicit format string and optional timezone.

## Parameters

- **x** (`String`): | Vector[String] The string(s) to parse.

- **format** (`String`): The strptime-style format string.

- **tz** (`String`): (Optional) Timezone label.


## Returns

| Vector[Datetime] The parsed datetime(s).

