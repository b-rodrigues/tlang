# prop_map_gen

Transform a generated value

Returns a generator spec that draws a value from `source`, applies `fn` to it, and yields the result.

## Parameters

- **source** (`Dict`): The source generator.

- **fn** (`Function`): A function from the generated value to a new value.


## Returns

A generator spec.

## Examples

```t
g = prop_map_gen(prop_gen_int_range(0, 10), \(v) v * 2)
```

## See Also

[prop_resize](prop_resize.html), [prop_such_that](prop_such_that.html)

