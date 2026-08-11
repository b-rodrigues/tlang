# prop_gen_vector

Generate a random Vector

Returns a generator spec producing a Vector of `n` elements drawn from the `elem` generator.

## Parameters

- **elem** (`Dict`): The element generator.

- **n** (`Int`): The vector length.


## Returns

A generator spec.

## Examples

```t
assert(prop_for_all(prop_gen_vector(prop_gen_int(), 10), \(v) length(v) == 10))
```

## See Also

[prop_gen_list](prop_gen_list.html)

