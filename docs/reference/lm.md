# lm

Linear Model

Fits a linear regression model using Ordinary Least Squares (OLS).

## Parameters

- **formula** (`Formula`): The model formula (e.g., mpg ~ wt + hp).
- **data** (`DataFrame`): The data to use.

## Returns

A model object containing coefficients, residuals, and statistics.

## Examples

```t
model = lm(mpg ~ wt + hp, data: mtcars)
summary(model)
```

## See Also

[add_diagnostics](add_diagnostics.md), [fit_stats](fit_stats.md), [summary](summary.md)

