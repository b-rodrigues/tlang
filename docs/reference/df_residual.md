# df_residual

Residual Degrees of Freedom

Returns the residual degrees of freedom of a model.

## Parameters

- **model** (`Model`): The model object.

## Returns:

Returns: The residual degrees of freedom.

## Examples

```t
model = lm(mpg ~ wt, data = mtcars)
df = df_residual(model)
```

