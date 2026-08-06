# prop_such_that

Filter generated values by a predicate

Returns a generator spec that draws values from `source` and keeps only those for which `pred` returns true. Gives up (with an error) after `max_tries` consecutive failures.

## Parameters

- **source** (`Dict`): The source generator.

- **pred** (`Function`): A Bool-returning predicate on generated values.

- **max_tries** (`Int`): = 100 Retry limit before giving up.


## Returns

A generator spec.

## Examples

```t
g = prop_such_that(prop_gen_int_range(-10, 10), \(x) x != 0)
```

## See Also

[prop_map_gen](prop_map_gen.html)

