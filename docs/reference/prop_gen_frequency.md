# prop_gen_frequency

Generate a value from weighted generators

Returns a generator spec that picks one of the supplied generators with probability proportional to its weight.

## Parameters

- **pairs** (`List[[Int,`): Dict]] A list of `[weight, generator]` pairs.


## Returns

A generator spec.

## Examples

```t
g = prop_gen_frequency([[5, prop_gen_int()], [1, prop_gen_bool()]])
```

## See Also

[prop_gen_choice](prop_gen_choice.html)

