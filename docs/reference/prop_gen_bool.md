# prop_gen_bool

Generate a random Bool

Returns a generator spec producing Bool values (true or false).

## Returns

A generator spec.

## Examples

```t
assert(prop_for_all(prop_gen_bool(), \(x) x == true || x == false))
```

## See Also

[prop_gen_int](prop_gen_int.html)

