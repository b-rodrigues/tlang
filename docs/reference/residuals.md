# residuals

Model Residuals

Computes residuals for a model given a dataset.

## Parameters

- **data** (`DataFrame`): Input data.
- **model** (`Model`): The model object.
- **type** (`String`): (Optional) Type of residuals = "response" (default) or "pearson".

## Returns:

Returns: Columns = `actual`, `fitted`, `resid`.

## Examples

```t
res = residuals(mtcars, model)
res_p = residuals(mtcars, model, type = "pearson")
```

