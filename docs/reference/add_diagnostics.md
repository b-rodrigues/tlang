# add_diagnostics

Augment Data with Model Calculations

Appends model predictions, residuals, and potentially diagnostic metrics to a dataset.

## Parameters

- **data** (`DataFrame`): The dataset to add_diagnostics.

- **model** (`Model`): The model object.


## Returns

The original DataFrame with appended `fitted`, `resid`, etc.

## Examples

```t
df = add_diagnostics(mtcars, model)
```

