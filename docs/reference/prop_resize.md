# prop_resize

Resize a generator

Returns a generator spec that draws from `source` with the size (number of elements/rows) of nested vector, list, and df generators overridden to `n`. Generators that do not carry their own size are unaffected.

## Parameters

- **source** (`Dict`): The generator to resize.

- **n** (`Int`): New size for nested vector/list/df generators.


## Returns

A generator spec.

## Examples

```t
g = prop_resize(prop_gen_vector(prop_gen_int(), 3), 20)
```

## See Also

[prop_map_gen](prop_map_gen.html)

