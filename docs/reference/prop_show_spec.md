# prop_show_spec

Render a generator spec back to T source

Inspects the `gen` Dict (as built by prop_gen_int, prop_gen_df, ...) and returns the T source that rebuilds a behaviorally equivalent generator: both produce identical values under the same seed. Closure-carrying generators (prop_map_gen, prop_such_that, prop_gen_fn) and unknown generator kinds cannot be rendered and raise an error.

## Parameters

- **spec** (`Dict`): A generator spec (see prop_gen_int, prop_gen_df, ...).


## Returns

T source that rebuilds the generator.

## Examples

```t
prop_show_spec(prop_gen_int_range(0, 100))
# "prop_gen_int_range(0, 100)"
```

## See Also

[prop_gen_int](prop_gen_int.html), [prop_for_all](prop_for_all.html)

