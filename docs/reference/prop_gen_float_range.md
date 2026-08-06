# prop_gen_float_range

Generate a random Float in a range

Returns a generator spec producing Float values drawn uniformly from [min, max).

## Parameters

- **min** (`Float`): Lower bound (inclusive).

- **max** (`Float`): Upper bound (exclusive).


## Returns

A generator spec.

## Examples

```t
assert(prop_for_all(prop_gen_float_range(0.0, 1.0), \(x) x >= 0.0))
```

## See Also

[prop_gen_int_range](prop_gen_int_range.html)

