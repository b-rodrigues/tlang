# Linear Models & Broom-Style Output

T provides `broom`-style model output for linear regression, making it easy to extract tidy coefficients, model-level statistics, and per-observation diagnostics — all as DataFrames ready for further analysis.

## Quick Example

```t
-- Load data
df = read_csv("housing.csv")

-- Fit a multi-predictor linear model
model = lm(data = df, formula = price ~ sqft + bedrooms)
-- Prints: {`formula`: price ~ sqft + bedrooms, `r_squared`: 0.87, ...}

-- Tidy coefficients table (like broom::tidy)
summary(model)
-- # A DataFrame: 3 × 5
--   term         estimate  std_error  statistic  p_value
--   (Intercept)  12500.0   3200.5     3.906      0.0012
--   sqft         125.3     8.2        15.28      0.0000
--   bedrooms     -8500.0   2400.1     -3.541     0.0032

-- Model-level statistics (like broom::glance)
fit_stats(model)
-- # A DataFrame: 1 × 12
--   r_squared  adj_r_squared  sigma  statistic  p_value  ...

-- Augment data with diagnostics (like broom::augment)
add_diagnostics(model, data = df)
-- # A DataFrame with original columns plus:
--   .fitted  .resid  .hat  .sigma  .cooksd  .std_resid
```

## The Four Functions

### `lm()` — Fit a Linear Model

```t
model = lm(data = df, formula = y ~ x1 + x2)
```

**Arguments:**
- `data` — a DataFrame containing the variables
- `formula` — a formula specifying the model (e.g. `y ~ x1 + x2`)

**Returns** a model object with these accessible fields:
- `model.formula` — the formula used
- `model.r_squared` — R²
- `model.adj_r_squared` — adjusted R²
- `model.sigma` — residual standard error
- `model.nobs` — number of observations

Printing the model shows a summary of these fields. Use `summary()`, `fit_stats()`, and `add_diagnostics()` to get detailed output.

### `summary()` — Tidy Coefficients Table

```t
summary(model)
```

Returns a DataFrame with one row per term:

| Column | Description |
|--------|-------------|
| `term` | Coefficient name (`"(Intercept)"`, `"x1"`, ...) |
| `estimate` | Point estimate (β̂) |
| `std_error` | Standard error of the estimate |
| `statistic` | t-statistic |
| `p_value` | Two-tailed p-value |

### `fit_stats()` — Model-Level Statistics

```t
fit_stats(model)
```

Returns a single-row DataFrame summarising the overall model fit:

| Column | Description |
|--------|-------------|
| `r_squared` | Coefficient of determination (R²) |
| `adj_r_squared` | Adjusted R² |
| `sigma` | Residual standard error |
| `statistic` | F-statistic for overall model |
| `p_value` | p-value of the F-test |
| `df` | Model degrees of freedom |
| `logLik` | Log-likelihood |
| `AIC` | Akaike information criterion |
| `BIC` | Bayesian information criterion |
| `deviance` | Residual sum of squares |
| `df_residual` | Residual degrees of freedom |
| `nobs` | Number of observations |

### `add_diagnostics()` — Per-Observation Diagnostics

```t
add_diagnostics(model, data = df)
```

Returns the original DataFrame with six diagnostic columns appended:

| Column | Description |
|--------|-------------|
| `.fitted` | Predicted values (ŷ) |
| `.resid` | Residuals (y − ŷ) |
| `.hat` | Leverage (diagonal of hat matrix) |
| `.sigma` | Leave-one-out residual standard error |
| `.cooksd` | Cook's distance |
| `.std_resid` | Standardised residuals |

## Full Walkthrough

### 1. Prepare and Fit

```t
df = read_csv("trees.csv")
model = lm(data = df, formula = Volume ~ Girth + Height)
-- Prints: {`formula`: Volume ~ Girth + Height, `r_squared`: 0.948, ...}
```

### 2. Inspect Coefficients

```t
s = summary(model)
s.term       -- ["(Intercept)", "Girth", "Height"]
s.estimate   -- [-57.99, 4.71, 0.34]
s.p_value    -- [0.0002, 0.0000, 0.0145]
```

### 3. Check Model Fit

```t
gs = fit_stats(model)
gs.r_squared      -- 0.948
gs.adj_r_squared  -- 0.944
gs.AIC            -- 176.9
```

### 4. Examine Diagnostics

```t
aug = add_diagnostics(model, data = df)
-- Find influential observations
filter(aug, .cooksd > 0.5)
-- Check for high-leverage points
filter(aug, .hat > 0.3)
```

### 5. Pipeline Integration

```t
df |> lm(formula = Volume ~ Girth + Height) |> fit_stats
```

## Multi-Predictor Support

```t
lm(data = df, formula = y ~ x)               -- single predictor
lm(data = df, formula = y ~ x1 + x2)         -- two predictors
lm(data = df, formula = y ~ x1 + x2 + x3)    -- many predictors
```

## Comparison with R's broom Package

| R (broom) | T equivalent |
|-----------|-------------|
| `broom::tidy(fit)` | `summary(model)` |
| `broom::glance(fit)` | `fit_stats(model)` |
| `broom::augment(fit, data)` | `add_diagnostics(model, data = df)` |

The outputs match R's broom package to within floating-point precision, verified by golden tests against reference values computed in R.
