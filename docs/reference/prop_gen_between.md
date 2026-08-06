# prop_gen_between

Generate a random Int within domain bounds

Returns a generator spec producing Int values drawn uniformly from [min, max] inclusive. Shrinking stays inside the domain: counterexamples shrink toward `min` (e.g. 137 -> 118 -> ... -> 101), never below it.

## Parameters

- **min** (`Int`): Lower bound (inclusive).

- **max** (`Int`): Upper bound (inclusive).


## Returns

A generator spec.

## Examples

```t
assert(prop_for_all(prop_gen_between(100, 200), \(x) x >= 100 && x <= 200))
```

## See Also

[prop_gen_int_range](prop_gen_int_range.html), [prop_gen_int](prop_gen_int.html)

