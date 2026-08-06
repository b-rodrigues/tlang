# prop_gen_factor

Generate a random Factor

Returns a generator spec producing a Factor value whose level is chosen uniformly from `levels`. When used as a column in prop_gen_df, one level is drawn per row.

## Parameters

- **levels** (`List[String]|String`): The factor levels.


## Returns

A generator spec.

## Examples

```t
g = prop_gen_factor(["low", "medium", "high"])
```

## See Also

[prop_gen_df](prop_gen_df.html)

