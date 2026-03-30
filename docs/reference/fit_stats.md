# fit_stats

Model Goodness-of-Fit Statistics

Returns a tidy DataFrame of model-level statistics (e.g. R-squared, AIC, BIC). Supports single model objects or labeled collections of models for comparison.  When passed a list or dictionary of models, it stacks the results into a single DataFrame, automatically adding a 'model' column if labels are present.

## Parameters

- **x** (`Model`): | List[Model] | Dict[String, Model] The model(s) to inspect.


## Returns

A tidy one-row-per-model summary of goodness-of-fit.

## Examples

```t
m1 = lm(mpg ~ wt, data = mtcars)
fit_stats(m1)
m2 = lm(mpg ~ hp + wt, data = mtcars)
fit_stats([Model_1: m1, Model_2 = m2])
```

## See Also

[summary](summary.html), [lm](lm.html)

