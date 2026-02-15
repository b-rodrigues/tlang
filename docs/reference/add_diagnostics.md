# add_diagnostics

Add Model Diagnostics

augments the data with model diagnostic columns (residuals, fitted values, etc.).

## Parameters

- **model** (`Model`): The model object.
- **data** (`DataFrame`): (Optional) The data to augment. Defaults to model data.

## Returns

The data with added diagnostic columns.

## Examples

```t
df = add_diagnostics(model)
```

## See Also

[lm](lm.md)

