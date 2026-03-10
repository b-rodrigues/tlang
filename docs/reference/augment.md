# augment

Augment Data with Model Calculations

Appends model predictions, residuals, and potentially diagnostic metrics to a dataset.

## Parameters

- **data** (`DataFrame`): The dataset to augment.

- **model** (`Model`): The model object.


## Returns

The original DataFrame with appended `fitted`, `resid`, etc.

## Examples

```t
aug = augment(mtcars, model)
```

