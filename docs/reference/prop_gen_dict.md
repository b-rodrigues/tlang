# prop_gen_dict

Generate a Dict

Returns a generator spec producing a Dict with one generated value per column. Each column's generator draws one value; `na_prob` controls the probability that any given column value is NA.

## Parameters

- **columns** (`Dict`): { name :: String : gen_spec :: Dict } A Dict mapping column names to generator specs.

- **na_prob** (`Float`): = 0.1 Probability of a column value being NA.


## Returns

A generator spec.

## Examples

```t
prop_gen_dict([x: prop_gen_int_range(0, 100),
name: prop_gen_string_from("abc", 1, 5)])
```

## See Also

[prop_gen_df](prop_gen_df.html)

