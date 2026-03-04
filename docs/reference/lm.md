# lm

Linear Model

Fits a linear regression model using Ordinary Least Squares (OLS).

## Parameters

- **data** (`DataFrame`): The data to use.
- **formula** (`Formula`): The model formula (e.g., mpg ~ wt + hp).

## Returns:

Returns: A model object containing coefficients, residuals, and statistics.

## Examples

```t
model = lm(mtcars, mpg ~ wt + hp)
summary(model)
```

## See Also

[add_diagnostics](add_diagnostics.html), [fit_stats](fit_stats.html), [summary](summary.html)

