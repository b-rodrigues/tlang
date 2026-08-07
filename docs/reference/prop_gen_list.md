# prop_gen_list

Generate a random List

Returns a generator spec producing a List of `n` elements drawn from the `elem` generator.

## Parameters

- **elem** (`Dict`): The element generator.

- **n** (`Int`): The list length.


## Returns

A generator spec.

## Examples

```t
assert(prop_for_all(prop_gen_list(prop_gen_int(), 4), \(xs) length(xs) == 4))
```

## See Also

[prop_gen_vector](prop_gen_vector.html)

