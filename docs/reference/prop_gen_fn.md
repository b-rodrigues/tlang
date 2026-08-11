# prop_gen_fn

Generate a value via a custom function

Returns a generator spec that draws a value by calling `fn(size)` with the current generation size, so generators can build on each other or on domain logic. `fn` may be any callable value.

## Parameters

- **fn** (`Function`): A function from the current size to a value.


## Returns

A generator spec.

## Examples

```t
g = prop_gen_fn(\(n) n * 2)
```

## See Also

[prop_map_gen](prop_map_gen.html)

