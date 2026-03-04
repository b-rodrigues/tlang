# sigma

Residual Standard Deviation

Returns the residual standard deviation (sigma) of a linear model. For GLMs, use `dispersion()` instead.

## Parameters

- **model** (`Model`): The model object.

## Returns:

Returns: The Residual Standard Error.

## Examples

```t
model = lm(mpg ~ wt, data = mtcars)
s = sigma(model)
```

## See Also

[dispersion](dispersion.html)

