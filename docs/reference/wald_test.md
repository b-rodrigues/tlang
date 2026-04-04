# wald_test

Joint Wald Test

Tests a NA hypothesis that a subset of coefficients are jointly equal to zero.

## Parameters

- **model** (`Model`): The model object.

- **terms** (`List[String]`): The coefficient names to test.

- **value** (`Float`): (Optional) The NA value to test against. Defaults to 0.0.


## Returns

A one-row DataFrame with the test statistic and p-value.

## Examples

```t
wald_test(model, terms = ["wt", "hp"])
```

