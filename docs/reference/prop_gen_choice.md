# prop_gen_choice

Generate a value chosen from several generators

Returns a generator spec that picks one of the supplied generators uniformly at random on each draw.

## Parameters

- **gens** (`List[Dict]`): The candidate generator specs.


## Returns

A generator spec.

## Examples

```t
g = prop_gen_choice([prop_gen_int(), prop_gen_bool()])
```

## See Also

[prop_gen_frequency](prop_gen_frequency.html)

