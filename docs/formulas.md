# Formulas in T

Formulas provide a declarative way to specify statistical models, inspired by R.

## Syntax

```t
response ~ predictor
```

The `~` operator creates a Formula object that can be passed to modeling functions.

## Examples

```t
-- Simple linear regression
model = lm(data = df, formula = y ~ x)

-- Multiple regression
model = lm(data = df, formula = y ~ x1 + x2 + x3)

-- Interaction terms
model = lm(data = df, formula = y ~ x1 * x2)
```

## Supported Functions

- `lm()` - Linear regression

## `lm()` - Linear Regression

Fit a linear model using least squares.

### Signature

```t
lm(data: DataFrame, formula: Formula, ...) -> Dict
```

### Arguments

- `data`: DataFrame containing the variables
- `formula`: Formula specifying the model (e.g., `y ~ x`)

### Returns

Dictionary containing:
- `formula`: The model formula
- `intercept`: Estimated intercept
- `slope`: Estimated slope (coefficient)
- `r_squared`: R² statistic
- `residuals`: Vector of residuals
- `n`: Number of observations
- `response`: Name of response variable
- `predictor`: Name of predictor variable

### Examples

```t
data = read_csv("mtcars.csv")
model = lm(data = data, formula = mpg ~ hp)
print(model.r_squared)
```

## Current Limitations

- Intercept control: `y ~ x + 1` vs `y ~ x - 1`
- Transformations: `y ~ log(x)`

---

## Next Steps

Now that you've explored formulas, learn about statistical modeling and pipelines in T:

1. **[Models and Prediction](models.md)** — Comprehensive guide to statistical models.
2. **[Pipeline Tutorial](pipeline_tutorial.md)** — Build reproducible data pipelines.
3. **[API Reference](api-reference.md)** — Complete function reference by package.
