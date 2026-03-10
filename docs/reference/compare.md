# compare

Compare Models

Align multiple model coefficient tables into a single wide DataFrame for comparison.

## Parameters

- **...** (`Variadic`): Models or a List of models to compare.


## Returns

A wide DataFrame with aligned terms and suffixed columns.

## Examples

```t
m1 = lm(mpg ~ wt, data = mtcars)
m2 = lm(mpg ~ wt + hp, data = mtcars)
compare(m1, m2)
```

