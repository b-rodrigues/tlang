# prop_gen_df_from

Generate a DataFrame matching an existing sample

Returns a generator spec producing a DataFrame with the same columns as `df`, inferring a per-column generator from the sample values: Int and Float bounds come from the observed min/max, Strings are drawn from the observed distinct values, Factors keep their levels, and Dates/Datetimes keep their observed range (and timezone).

## Parameters

- **df** (`DataFrame`): The sample data frame to match.

- **nrows** (`Int`): = 30 Number of rows to draw.

- **na_prob** (`Float`): = 0.1 Probability a cell is NA (0 to 1).


## Returns

A generator spec.

## Examples

```t
g = prop_gen_df_from(read_csv("mtcars.csv"), nrows = 100)
```

## See Also

[prop_gen_df](prop_gen_df.html)

