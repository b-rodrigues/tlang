# Statistical Models & Tidy Output

> [!IMPORTANT]
> **Native Support Note**: $T$ currently provides a native implementation for Linear Models (`lm`) for convenience. For more advanced modeling (GLMs, Mixed Models, Machine Learning), $T$ uses a "Polyglot" approach where models are trained in R or Python nodes and then consumed natively in T via PMML.

$T$ treats models as first-class objects that can be summarized and evaluated regardless of which runtime created them.

## Fitting Models

### `lm()` — Linear Regression (Native)
Fits an Ordinary Least Squares (OLS) model. Following $T$'s "Data First" philosophy, the dataset is the first argument.

```t
-- Positional: data, then formula
model = lm(mtcars, mpg ~ wt + hp)

-- Named args also supported
model = lm(data = mtcars, formula = mpg ~ wt + hp)
```

### Advanced Modeling (Polyglot)
To fit models beyond simple OLS, you should use `R` or `Python` nodes within a $T$ pipeline. These nodes produce a model object that is serialized to PMML, allowing $T$ to consume it natively for inspection and prediction.

#### Example: Logistic Regression in R
```t
p = pipeline {
    model_node = rn(
        command = <{
            glm(Survived ~ Pclass + Sex + Age, data = titanic, family = binomial())
        }>,
        serializer = "pmml"
    )
}
build_pipeline(p)
model = read_node("model_node")
summary(model) -- Fully supported in T!
```

---

## Model Inspection & Diagnostics

> [!TIP]
> **Native Convenience**: All model inspection and diagnostic functions are implemented natively in $T$. This means that even if a model was originally trained in R or Python (and imported via PMML), you can perform summaries, calculate residuals, and run hypothesis tests **without** needing an active R or Python environment. This approach provides significant speed advantages and simplifies high-performance pipelines.

$T$ adopts the `broom` philosophy: model outputs should be DataFrames or Tidy Dictionaries.

### `summary(model)`
Returns a tidy representation of coefficients. 
* For native `lm`, it returns a DataFrame. 
* For some imported models, it returns a Dict where the tidy DataFrame is in `_tidy_df`.

```t
s = summary(model)
s._tidy_df
-- # A DataFrame: 3 × 5
--   term         estimate  std_error  statistic  p_value
```

### `coef(model)`
A convenience function that returns a two-column DataFrame with just `term` and `estimate`.

### `fit_stats(model)`
Returns a single-row DataFrame of model-level statistics (R-squared, AIC, BIC, etc.).

```t
stats = fit_stats(model)
-- # A DataFrame: 1 × 15
--   r_squared  adj_r_squared  aic    bic    nobs
```

### `conf_int(model, level = 0.95)`
Computes confidence intervals for model coefficients.

```t
ci = conf_int(model, level: 0.99)
-- # A DataFrame: 3 × 3
--   term         lower     upper
```

### `compare(model1, model2, ...)`
Aligns multiple model coefficient tables into a single wide DataFrame for side-by-side comparison.

```t
comp = compare(m1, m2)
-- Returns DataFrame with columns: estimate_1, std_error_1, ..., estimate_2, ...
```

### `augment(data, model)`
Augments the original data with core model-based columns: `fitted`, `resid`, and `std_resid`.

```t
aug = augment(mtcars, model)
-- Adds columns: fitted, resid, std_resid
```

### `add_diagnostics(data, model)`
Similar to `augment`, but adds a more comprehensive set of diagnostic columns (leverage, influence, etc.).

```t
diag = add_diagnostics(mtcars, model)
-- Adds columns: fitted, resid, hat, sigma, cooksd, std_resid
```

### `residuals(data, model, type = "response")`
Returns a DataFrame containing the `actual` response, the `fitted` values, and the calculated `resid` (residuals).

```t
res = residuals(mtcars, model, type: "pearson")
-- # A DataFrame: 32 × 3 [actual, fitted, resid]
```

---

## Hypothesis Testing & Diagnostics

### `anova(model1, model2, ...)`
Performs Analysis of Variance (ANOVA) comparing two or more nested models.

```t
m1 = lm(mtcars, mpg ~ wt)
m2 = lm(mtcars, mpg ~ wt + hp + qsec)
av = anova(m1, m2)
-- Returns an ANOVA table with Statistics and P-values
```

### `wald_test(model, terms, value = 0.0)`
Performs a joint Wald test on a subset of model coefficients.

```t
-- Test if both 'hp' and 'qsec' are jointly equal to zero
w = wald_test(model, terms: ["hp", "qsec"])
```

### `vcov(model)`
Returns the Variance-Covariance matrix of the coefficients as a square DataFrame.

```t
v = vcov(model)
```

---

## Prediction

The `predict(data, model)` function performs vectorized predictions natively in $T$. 

```t
-- Fast, native evaluation in T
-- Even if the model was trained in R or Python (and imported via PMML)
preds = predict(new_data, model)
```

$T$ supports various link functions for GLMs (imported via PMML), including **Logit**, **Probit**, **Log**, **Inverse**, and **Cloglog**.

---

## Model Interchange & PMML

### Why PMML?
The **Predictive Model Markup Language (PMML)** is the bridge between $T$ and other runtimes. It allows:
1. **R Integration**: Using any R model that has a PMML exporter (e.g. `stats::glm`, `survival::coxph`).
2. **Python Integration**: Using `scikit-learn` or `statsmodels`.
3. **Reproducibility**: Models persist independently of the original runtime code.

### Cross-Runtime Consistency
$T$'s statistical evaluator is verified against R's reference implementation. Results match R's `broom::tidy()` and `stats::predict()` exactly.

---

## Comparison with R's broom Package

| R (broom) / stats | T equivalent |
|-------------------|--------------|
| `broom::tidy(fit)` | `summary(model)` |
| `broom::glance(fit)` | `fit_stats(model)` |
| `broom::augment(fit, data)` | `augment(df, model)` |
| `stats::residuals(fit)` | `residuals(df, model)`|
| `stats::coef(fit)` | `coef(model)` |
| `stats::vcov(fit)` | `vcov(model)` |
| `stats::anova(m1, m2)` | `anova(m1, m2)` |
| `survey::regTermTest` | `wald_test(model, terms)` |
