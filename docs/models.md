# Statistical Models & Tidy Output

> [!IMPORTANT]
> **Native Support Note**: $T$ provides native implementations for Linear Models (`lm`) and PMML-imported **Decision Trees** and **Random Forests**. For other advanced modeling (GLMs, Mixed Models, Machine Learning), $T$ uses a polyglot approach where models are trained in R or Python nodes and exchanged through PMML or ONNX.

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
To fit models beyond simple OLS, use `R` or `Python` nodes within a $T$ pipeline. These nodes can serialize model artifacts through PMML or ONNX depending on the scoring path you want.

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

#### Example: Logistic Regression in Python via ONNX
```t
p = pipeline {
    model_node = pyn(
        command = <{
            from sklearn.linear_model import LogisticRegression
            clf = LogisticRegression().fit(X, y)
            clf
        }>,
        serializer = ^onnx
    )
}
build_pipeline(p)
model = read_node("model_node")
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
For PMML decision trees and random forests, this includes tree metadata such as `n_trees`, `n_features`, `model_type`, and `mining_function`.

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

The `predict(data, model)` function performs vectorized predictions natively in $T$ for native, PMML-backed, and ONNX-backed models.

```t
-- Fast, native evaluation in T
-- Even if the model was trained in R or Python (and imported via PMML)
preds = predict(new_data, model)
```

$T$ supports various link functions for GLMs (imported via PMML), including **Logit**, **Probit**, **Log**, **Inverse**, and **Cloglog**.

> **PMML Trees & Boosting**: $T$ can now evaluate PMML-imported **Decision Trees**, **Random Forests**, and **XGBoost (GBTree)** models natively (no external runtime). This includes PMML exports from **scikit-learn** via `sklearn2pmml`. Use `t_read_pmml()` to load the model and `predict(df, model)` to score new data.

> **ONNX Native Inference**: $T$ can run ONNX models natively through ONNX Runtime using `t_read_onnx()` plus `predict(df, model)`. The current implementation supports single-input/single-output models and expects the selected numeric feature columns to match the model input width.

---

## Model Interchange: PMML and ONNX

### Why PMML?
The **Predictive Model Markup Language (PMML)** is the bridge between $T$ and other runtimes when you want T-native scoring. It allows:
1. **R Integration**: Using any R model that has a PMML exporter (e.g. `stats::glm`, `survival::coxph`).
2. **Python Integration**: Using `scikit-learn` or `statsmodels`.
3. **Reproducibility**: Models persist independently of the original runtime code.

### Why ONNX?
**ONNX** is the preferred interchange format when you want broad ML model coverage or faster native inference through ONNX Runtime. It allows:
1. **Python ML Export**: `scikit-learn` models via `skl2onnx`.
2. **Native T Loading**: Reading models with `t_read_onnx(path)` and scoring them with `predict(data, model)`.
3. **R/Python Runtime Loading**: Reading models via the `onnx` R package or Python `onnxruntime`.
4. **Broader Coverage**: Neural-network and non-PMML model families that PMML cannot represent well.

Use `^pmml` when you want T's hand-written classical-model evaluator. Use `^onnx` when you want a portable model artifact with native ONNX Runtime inference in T or cross-runtime execution in Python/R.

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

---

## Next Steps

Now that you can fit and inspect statistical models, explore how to build reproducible data pipelines and manage projects in T:

1. **[Pipeline Tutorial](pipeline_tutorial.md)** — Learn how to build reproducible, DAG-based data analysis workflows.
2. **[PMML Tutorial](pmml_tutorial.md)** — Learn the supported PMML workflows for moving models between R, Python, and T.
3. **[Project Development](project_development.md)** — Master T's project structure and dependency management.
4. **[Package Development](package_development.md)** — Create reusable T libraries.
5. **[API Reference](api-reference.md)** — Complete function reference by package.
