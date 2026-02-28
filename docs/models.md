# Statistical Models & Tidy Output

> [!IMPORTANT]
> **API Evolution Note**: $T$ currently supports Linear Models (`lm`) and Generalized Linear Models (`glm`). These are implemented with a `broom`-style output architecture to facilitate tidy data workflows.

$T$ provides a comprehensive suite of functions for fitting, inspecting, and predicting with statistical models. Whether the model is trained in $T$, R, or Python, $T$ treats it as a first-class object that can be summarized and evaluated natively.

## Fitting Models

### `lm()` — Linear Regression
Fits an Ordinary Least Squares (OLS) model.
```t
model = lm(Volume ~ Girth + Height, data = trees)
```

### `glm()` — Generalized Linear Models
Fits common GLMs (Logistic, Poisson, etc.) using Iteratively Reweighted Least Squares (IRLS).
```t
model = glm(Survived ~ Pclass + Age, data = titanic, family = "binomial")
```

---

## Model Inspection (Broom-Style)

$T$ adopts the `broom` philosophy from R: model outputs should be DataFrames.

### `summary(model)`
Returns a tidy DataFrame of coefficients (estimates, standard errors, statistics, and p-values).
```t
s = summary(model)
-- # A DataFrame: 3 × 5
--   term         estimate  std_error  statistic  p_value
--   (Intercept)  12.5      3.2        3.906      0.0012
--   sqft         125.3     8.2        15.28      0.0000
```

### `coef(model)`
A convenience function that returns a two-column DataFrame with just `term` and `estimate`.
```t
estimates = coef(model)
-- # A DataFrame: 3 × 2
--   term         estimate
--   (Intercept)  12.5
--   sqft         125.3
```

### `conf_int(model, level = 0.95)`
Computes confidence intervals for model coefficients using the Student's t distribution. 
```t
ci = conf_int(model, level: 0.99)
-- # A DataFrame: 3 × 3
--   term         lower     upper
--   (Intercept)  4.25      20.75
```

### `fit_stats(model)`
Returns a single-row DataFrame of model-level statistics (R-squared, AIC, BIC, Deviance, Log-Likelihood).
```t
stats = fit_stats(model)
-- # A DataFrame: 1 × 15
--   r_squared  adj_r_squared  aic    bic    nobs
--   0.87       0.85           125.4  130.2  100
```

### `add_diagnostics(model, data)`
Augments the original data with per-observation residuals, fitted values, leverage (`.hat`), and influence measures (`.cooksd`).
```t
aug = add_diagnostics(model, data)
filter(aug, .cooksd > 0.5)
```

---

## Prediction

The `predict()` function performs vectorized predictions on new data. Importantly, if a model was imported from R or Python via PMML, $T$ performs the calculation **natively in the $T$ evaluator** without requiring the original runtime to be present.

```t
-- Fast, native evaluation in T
preds = predict(new_data, model)
```

---

## Model Interchange & PMML

### Why PMML?
The **Predictive Model Markup Language (PMML)** is an XML-based standard for sharing models across different systems. $T$ uses PMML as a bridge to allow:
1. **R Integration**: Training models in R and using them in $T$ pipelines.
2. **Python Integration**: Training models in `scikit-learn` or `statsmodels` and using them in $T$ pipelines.
3. **Reproducibility**: Models are saved in a transparent, readable format that persists independently of the code that created them.

### Cross-Runtime Consistency
$T$'s statistical evaluator is verified against R's reference implementation. When you use `summary()`, `predict()`, or `conf_int()` on a model in $T$, the results match R's `broom::tidy()` and `stats::predict()` to within floating-point precision.

### Pipeline Example
```t
p = pipeline {
  model_node = node(
    command = <{ 
      import statsmodels.api as sm
      X = sm.add_constant(data_node[["wt", "hp"]])
      y = data_node["mpg"]
      sm.GLM(y, X, family=sm.families.Gaussian()).fit()
    }>,
    runtime = Python,
    serializer = "pmml"
  );
  
  predict_node = node(
    command = <{ predict(data_node, model_node) }>,
    runtime = T, -- No Python needed here!
    deserializer = [model_node: "pmml"]
  )
}
```

---

## Comparison with R's broom Package

| R (broom) | T equivalent |
|-----------|-------------|
| `broom::tidy(fit)` | `summary(model)` |
| `broom::glance(fit)` | `fit_stats(model)` |
| `broom::augment(fit, data)` | `add_diagnostics(model, data = df)` |

The outputs are designed to be drop-in replacements for R's tidy modeling workflow.
