# stats

Statistical summaries and models.

## Functions

| Function | Description |
|----------|-------------|
| `mean(x, weights = NA)` | Arithmetic mean of a numeric list/vector, optionally weighted |
| `sd(x, weights = NA)` | Standard deviation, optionally weighted |
| `quantile(x, p, weights = NA)` | Compute quantile at probability p, optionally weighted |
| `cor(x, y, weights = NA)` | Pearson correlation coefficient, optionally weighted |
| `lm(data, formula, weights = NA)` | Linear regression / weighted least squares model object |
| `summary(model)` | Tidy coefficients table (like `broom::tidy`) |
| `fit_stats(model)` | Goodness-of-fit statistics (like `broom::fit_stats`) |
| `add_diagnostics(model, data)` | Augment data with diagnostics (like `broom::augment`) |
| `min(x)` | Minimum value |
| `max(x)` | Maximum value |
| `median(x, na_rm = false, weights = NA)` | Median value, optionally weighted |
| `var(x, na_rm = false, weights = NA)` | Variance, optionally weighted |
| `cov(x, y, na_rm = false, weights = NA)` | Covariance, optionally weighted |
| `range(x, na_rm = false)` | Min/max as a length-2 vector |
| `iqr(x, na_rm = false, weights = NA)` | Interquartile range, optionally weighted |
| `mad(x, na_rm = false)` | Median absolute deviation (scaled) |
| `skewness(x, na_rm = false, weights = NA)` | Distribution skewness, optionally weighted |
| `kurtosis(x, na_rm = false, weights = NA)` | Excess kurtosis, optionally weighted |
| `mode(x)` | Most frequent value |
| `cv(x, na_rm = false, weights = NA)` | Coefficient of variation (sd / mean), optionally weighted |
| `fivenum(x, na_rm = false, weights = NA)` | Five-number summary, optionally weighted |
| `trimmed_mean(x, trim, weights = NA)` | Mean after trimming both tails, optionally weighted |
| `winsorize(x, limits, weights = NA)` | Cap tails by quantile limits, optionally weighted |
| `huber_loss(x, delta)` | Robust Huber loss |
| `scale(x)` / `standardize(x)` | z-score standardization |
| `normalize(x)` | Min-max scaling to [0,1] |
| `predict(data, model)` | Vectorized prediction |
| `anova(m1, m2)` | Compare nested models |
| `pnorm(x)` | Normal distribution CDF |
| `pt(x, df)` | Student-t CDF |
| `pf(q, df1, df2)` | F-distribution CDF |
| `pchisq(q, df)` | Chi-squared CDF |
| `poly(x, degree)` | Polynomial basis expansion |
| `cut(x, breaks)` | Discretize numeric vector |
| `read_onnx(path)` | Import ONNX model |
| `read_pmml(path)` | Import PMML model |

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
