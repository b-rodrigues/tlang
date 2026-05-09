# augment

Add Model Diagnostics

augments the data with model diagnostic columns (residuals, fitted values, etc.).

## Parameters

- **data** (`DataFrame`): (Optional) The data to augment.

- **model** (`Model`): The model object.


## Returns

The data with added diagnostic columns.

## Examples

```t
df = augment(mtcars, model)
```

## See Also

[lm](lm.html)

