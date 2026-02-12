# stats

Statistical summaries and models.

## Functions

| Function | Description |
|----------|-------------|
| `mean(x)` | Arithmetic mean of a numeric list/vector |
| `sd(x)` | Standard deviation |
| `quantile(x, p)` | Compute quantile at probability p |
| `cor(x, y)` | Pearson correlation coefficient |
| `lm(data, formula)` | Linear regression model object |
| `summary(model)` | Tidy coefficients table (like `broom::tidy`) |
| `fit_stats(model)` | Goodness-of-fit statistics (like `broom::glance`) |
| `add_diagnostics(model, data)` | Augment data with diagnostics (like `broom::augment`) |
| `min(x)` | Minimum value |
| `max(x)` | Maximum value |

## Examples

```t
mean([1, 2, 3, 4, 5])          -- 3.0
sd([1, 2, 3, 4, 5])            -- 1.5811...
quantile([1, 2, 3, 4, 5], 0.5) -- 3
min([3, 1, 2])                  -- 1
max([3, 1, 2])                  -- 3

-- Linear regression (multi-predictor)
model = lm(data = df, formula = y ~ x1 + x2)
model                        -- prints: {formula, r_squared, adj_r_squared, sigma, nobs}
summary(model)               -- coefficients table (term, estimate, std_error, statistic, p_value)
fit_stats(model)             -- R², adj R², sigma, F-stat, AIC, BIC, etc.
add_diagnostics(model, data = df)  -- original data + .fitted, .resid, .hat, .cooksd, etc.
```

## Status

Built-in package — included with T by default.
