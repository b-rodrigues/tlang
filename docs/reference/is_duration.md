# is_duration

Test for Duration values

Returns true for Duration values, false for anything else.

## Parameters

- **x** (`Any`): The value to test.


## Returns

True for Duration values.

## Examples

```t
is_duration(ymd_hms("2024-01-15 10:30:45") - ymd_hms("2024-01-14 10:30:45"))
```

