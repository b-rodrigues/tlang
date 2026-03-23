# anova

Analysis of Variance (ANOVA)

Compares nested models using F-tests (for linear models) or Chi-square tests (for GLMs).

## Parameters

- **...** (`Model`): One or more model objects to compare.


## Returns

ANOVA table with statistics and p-values.

## Examples

```t
m1 = lm(mpg ~ wt, data = mtcars)
m2 = lm(mpg ~ wt + hp, data = mtcars)
anova(m1, m2)
```

