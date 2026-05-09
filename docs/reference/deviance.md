# deviance

Model Deviance

Returns the deviance of a model.

## Parameters

- **model** (`Model`): The model object.


## Returns

The deviance.

## Examples

```t
model = lm(mpg ~ wt, data = mtcars)
dev = deviance(model)
```

