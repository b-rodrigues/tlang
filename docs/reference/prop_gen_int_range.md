# prop_gen_int_range

Generate a random Int in a fixed range

Returns a generator spec producing Int values drawn uniformly from [min, max] inclusive.

## Parameters

- **min** (`Int`): Lower bound (inclusive).

- **max** (`Int`): Upper bound (inclusive).


## Returns

A generator spec.

## Examples

```t
assert(prop_for_all(prop_gen_int_range(0, 5), \(x) x >= 0 && x <= 5))
```

## See Also

[prop_gen_float_range](prop_gen_float_range.html), [prop_gen_int](prop_gen_int.html)

