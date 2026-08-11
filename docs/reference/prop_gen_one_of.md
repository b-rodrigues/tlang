# prop_gen_one_of

Generate a value chosen from a fixed set

Returns a generator spec that picks one value uniformly at random from `values` on each draw.

## Parameters

- **values** (`List[Any]`): | Vector[Any] The candidate values.


## Returns

A generator spec.

## Examples

```t
g = prop_gen_one_of(["red", "green", "blue"])
```

## See Also

[prop_gen_choice](prop_gen_choice.html)

