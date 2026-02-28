# score

Model Scoring

Calculates various performance metrics (RMSE, MAE, R-squared, etc.) for a model on a dataset.

## Parameters

- **data** (`DataFrame`): The dataset to score.
- **model** (`Model`): The model object.

## Returns

A one-row DataFrame with metrics.

## Examples

```t
metrics = score(test_data, model)
```

