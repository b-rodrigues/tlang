# summary

Model Summary

Returns a tidy DataFrame of regression coefficients and statistics.

## Parameters

- **model** (`Model`): The model object (e.g., from lm()).

## Returns

Tidy summary dictionary with `_tidy_df` and metadata.

## Examples

```t
s = summary(model)
coefficients = s._tidy_df
```

## See Also

[fit_stats](fit_stats.md), [lm](lm.md)

