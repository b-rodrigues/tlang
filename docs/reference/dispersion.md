# dispersion

Dispersion Parameter

Returns the dispersion parameter of a Generalized Linear Model (GLM). For linear models (lm), use `sigma()` instead.

## Parameters

- **model** (`Model`): The model object.

## Returns:

Returns: The dispersion parameter.

## Examples

```t
model = glm(survived ~ age, data = df, family = "binomial")
d = dispersion(model)
```

## See Also

[sigma](sigma.md)

