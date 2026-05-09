# lm

Linear Model

Fits a linear regression model using Ordinary Least Squares (OLS).

## Parameters

- **data** (`DataFrame`): The data to use.

- **formula** (`Formula`): The model formula (e.g., mpg ~ wt + hp).

- **weights** (`Vector[Float]`): | List[Float] = NA Optional non-negative observation weights for weighted least squares.


## Returns

A model object containing coefficients, residuals, and statistics.

## Examples

```t
model = lm(mtcars, mpg ~ wt + hp)
summary(model)
```

## See Also

[augment](augment.html), [fit_stats](fit_stats.html), [summary](summary.html)

