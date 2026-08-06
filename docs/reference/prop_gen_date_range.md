# prop_gen_date_range

Generate a Date or Datetime in a range

Returns a generator spec that draws a Date uniformly between `start` and `end` (inclusive). Bounds must be both Dates or both Datetimes; a Datetime range keeps the start bound's timezone. Use `parse_date`, `today`, or `parse_datetime` to build bounds.

## Parameters

- **start** (`Date`): | Datetime Lower bound (inclusive).

- **end** (`Date`): | Datetime Upper bound (inclusive).


## Returns

A generator spec.

## Examples

```t
g = prop_gen_date_range(parse_date("2020-01-01"), parse_date("2020-12-31"))
```

## See Also

[today](today.html), [parse_date](parse_date.html), [prop_gen_int_range](prop_gen_int_range.html)

