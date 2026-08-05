# prop_gen_df

Generate a random DataFrame

Returns a generator spec producing a DataFrame with one column per entry in `columns` (a Dict mapping column names to generator specs). Each column has `nrows` rows; with probability `na_prob`, a cell is replaced with a typed NA matching the column's generator.

## Parameters

- **columns** (`Dict[String,`): Dict] Column name -> generator spec.

- **nrows** (`Int`): = 30 Number of rows.

- **na_prob** (`Float`): = 0.1 Probability a cell is NA (0 to 1).


## Returns

A generator spec.

## Examples

```t
g = prop_gen_df([x: prop_gen_float_range(0.0, 100.0),
grp: prop_gen_factor(["a", "b"])],
nrows = 50, na_prob = 0.05)
```

## See Also

[prop_gen_factor](prop_gen_factor.html)

