# prop_gen_int

Generate a random Int

Returns a generator spec producing Int values drawn uniformly from the optional `min`/`max` range (defaults: -10 to 10, inclusive).

## Parameters

- **min** (`Int`): = -10 Lower bound (inclusive).

- **max** (`Int`): = 10 Upper bound (inclusive).


## Returns

A generator spec.

## Examples

```t
assert(prop_for_all(prop_gen_int(), \(x) x == x))
```

## See Also

[prop_gen_float_range](prop_gen_float_range.html), [prop_gen_int_range](prop_gen_int_range.html)

