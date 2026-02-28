# nobs

Number of Observations

Returns the number of observations used to fit a model.

## Parameters

- **model** (`Model`): The model object.

## Returns

The number of observations.

## Examples

```t
model = lm(mpg ~ wt, data: mtcars)
n = nobs(model)
```

