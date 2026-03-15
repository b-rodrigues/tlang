# n_distinct

Count distinct values

Returns the number of distinct values in a vector or list. Inside `summarize()`, this acts as an aggregation expression.

## Parameters

- **x** (`Vector`): | List The input values.


## Returns

The number of distinct values.

## Examples

```t
summarize(df, $unique_species = n_distinct($species))
```

## See Also

[summarize](summarize.html), [distinct](distinct.html)
