# conf_int

Confidence Intervals for Model Coefficients

Computes confidence intervals for model coefficients based on the Student's t distribution.

## Parameters

- **model** (`Model`): The model object (e.g., from lm() or imported).
- **level** (`Float`): Confidence level (default 0.95).

## Returns:

Returns: Columns = `term`, `lower`, `upper`.

## Examples

```t
conf_int(model)
conf_int(model, 0.99)
```

## See Also

[summary](summary.md), [coef](coef.md)

