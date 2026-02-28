# coef

Model Coefficients

Extracts the coefficient estimates from a model object, keyed by term name.

## Parameters

- **model** (`Model`): The model object (e.g., from lm() or imported).

## Returns

Coefficient estimates with columns `term` and `estimate`.

## Examples

```t
coef(model)
```

## See Also

[conf_int](conf_int.md), [summary](summary.md)

