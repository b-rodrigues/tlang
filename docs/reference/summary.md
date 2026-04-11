# summary

Model Summary

Returns a tidy summary DataFrame for native models.

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

[fit_stats](fit_stats.html), [lm](lm.html)

