# prop_gen_ymd

Generate a Date within a year span

Returns a generator spec that draws a Date uniformly between January 1st of `min_year` and December 31st of `max_year` (both inclusive). Dates shrink toward `min_year`-01-01. Use `prop_gen_date_range` when you need arbitrary (non-year-aligned) bounds.

## Parameters

- **min_year** (`Int`): Lower bound year (inclusive).

- **max_year** (`Int`): Upper bound year (inclusive).


## Returns

A generator spec.

## Examples

```t
g = prop_gen_ymd(2000, 2024)
```

## See Also

[make_date](make_date.html), [prop_gen_date_range](prop_gen_date_range.html)

