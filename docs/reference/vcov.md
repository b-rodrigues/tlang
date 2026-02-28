# vcov

Variance-Covariance Matrix

Returns the variance-covariance matrix of the model coefficients. For native T models, the full matrix is returned. For imported models, a diagonal matrix based on standard errors is returned as a fallback.

## Parameters

- **model** (`Model`): The model object.

## Returns

A square matrix representation with term names.

## Examples

```t
model = lm(mpg ~ wt, data: mtcars)
v = vcov(model)
```

