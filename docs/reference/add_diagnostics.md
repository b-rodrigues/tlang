# add_diagnostics

Add Model Diagnostics

augments the data with model diagnostic columns (residuals, fitted values, etc.).

## Parameters

- **data** (`DataFrame`): (Optional) The data to augment.
- **model** (`Model`): The model object.

## Returns:

Returns: The data with added diagnostic columns.

## Examples

```t
df = add_diagnostics(mtcars, model)
```

## See Also

[lm](lm.html)

