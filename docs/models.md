# Statistical Models & Tidy Output

> [!IMPORTANT]
> **Native Support Note**: $T$ provides native implementations for Linear Models (`lm`) and PMML-imported **Decision Trees** and **Random Forests**. For other advanced modeling (GLMs, Mixed Models, Machine Learning), $T$ uses a polyglot approach where models are trained in R, Python, or Julia nodes and exchanged through PMML or ONNX.

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
To fit models beyond simple OLS, use `R`, `Python`, or `Julia` nodes within a $T$ pipeline. These nodes can serialize model artifacts through PMML or ONNX depending on the scoring path you want.

#### Example: Logistic Regression in R
```t
p = pipeline {
    model_node = rn(
        command = <{
            glm(Survived ~ Pclass + Sex + Age, data = titanic, family = binomial())
        }>,
        serializer = ^pmml
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

#### Example: Neural Network in Julia (Flux)
Julia nodes are particularly powerful for deep learning. $T$ handles Julia's "World Age" issues automatically, allowing you to train complex Flux models and export them as ONNX artifacts.

```t
p = pipeline {
    model_node = jln(
        command = <{
            using Flux, ONNX
            model = Chain(Dense(2, 10, relu), Dense(10, 1, sigmoid))
            # ... training logic ...
            model
        }>,
        serializer = ^onnx
    )
}
build_pipeline(p)
model = read_node("model_node")
predict(new_data, model) -- Native ONNX scoring in T
```

---

## Model Inspection & Diagnostics

> [!TIP]
> **Native Convenience**: All model inspection and diagnostic functions are implemented natively in $T$. This means that even if a model was originally trained in R or Python (and imported via PMML), you can perform summaries, calculate residuals, and run hypothesis tests **without** needing an active R or Python environment. This approach provides significant speed advantages and simplifies high-performance pipelines.

$T$ adopts the `broom` philosophy: model outputs should be DataFrames or Tidy Dictionaries.

### `summary(model)`
Returns a tidy representation of coefficients. It returns a `Dict` where the tidy `DataFrame` is in `_tidy_df`.

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

### `add_diagnostics(data, model)`
Augments the original data with core model-based columns: `fitted`, `resid`, and `std_resid`.

```t
aug = add_diagnostics(mtcars, model)
-- Adds columns: fitted, resid, std_resid
```

### `add_diagnostics(data, model)`
Similar to `add_diagnostics`, but adds a more comprehensive set of diagnostic columns (leverage, influence, etc.).

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

### Inspecting Foreign Models (`explain(p.node).foreign_meta`)

In polyglot pipelines, nodes frequently train models using **R**, **Python**, or **Julia** that cannot be converted to PMML/ONNX, or that produce complex objects (such as time-series fits, deep neural networks, mixed-effects regressions, or Bayesian Markov chains) stored in native formats (`.rds`, `.pkl`, `.jld2`).

While native T models can be passed directly to `summary()` or `fit_stats()`, inspecting foreign models traditionally required starting the foreign runtime and deserializing large artifacts into memory.

To eliminate this overhead, $T$ provides **zero-cost build-time foreign metadata introspection**:

1. **Automatic sidecar generation**: During Nix derivation execution in the sandbox, $T$'s runtime emitters (`r_save_meta`, `py_save_meta`, `jl_save_meta`) automatically inspect the returned object and write an uncompressed JSON metadata sidecar (`$out/meta`) alongside the artifact.
2. **Instant access**: In $T$, calling `explain(p.node_name)` exposes this sidecar under `.foreign_meta`. It can be queried in milliseconds without loading the artifact or initializing R, Python, or Julia.
3. **CLI & Agent inspection**: From the shell, `t explain --node p.node_name` (and `t explain --json --node p.node_name`) prints the metadata and DAG lineage.

#### Supported Metadata Fields

The `foreign_meta` dictionary exposes the following normalized fields when present:

| Field | Description | Supported Families / Examples |
|:---|:---|:---|
| `kind` | Value kind | `"model"`, `"time_series"`, `"forecast"`, `"chain"`, `"graph"`, `"dataset"`, `"image"`, `"optimization"`, `"ode"`, `"distribution"`, `"transformer"`, `"dataframe"`, `"matrix"` |
| `class` | Runtime type name | `"ARIMA"`, `"ets"`, `"Sequential"`, `"Chain"`, `"lme"`, `"ranger"`, `"SimpleGraph"` |
| `task` | Statistical / ML task | `"regression"`, `"classification"`, `"clustering"`, `"time_series"`, `"dim_reduction"`, `"density"`, `"anomaly_detection"`, `"ranking"`, `"survival"` |
| `dimensions` | Object shape | `[rows, cols]` for frames/matrices, `[dim]` for vectors, `[width, height]` for PIL images |
| `n_obs` | Training observations | Regression, classification, time series, survival models |
| `n_features` / `features` | Predictor counts & names | Feature column names, fitted coefficients (`lm`, `mgcv`, ARIMA `ar1`/`ma1`) |
| `n_params` | Parameter count | PyTorch (`torch.nn`), Keras / TensorFlow, Julia Flux, R6 keras/torch, `neuralnet` |
| `n_layers` | Layer count | Neural networks (PyTorch, Keras, Flux, R6) |
| `n_trees` | Tree count | Random Forest, `ranger`, XGBoost, CatBoost, LightGBM, `gbm` |
| `n_rounds` | Boosting rounds | Gradient boosted trees and rankers |
| `n_nodes` | Tree node count | Decision trees (`rpart`, `partykit::BinaryTree`), or graph vertices |
| `n_edges` | Graph edge count | `igraph` networks (R), `networkx` graphs (Python), `Graphs.jl` (Julia) |
| `n_clusters` | Cluster count | k-means, `Mclust`, `dbscan`, `clara`/`fanny`, `tslearn`, `Clustering.jl` |
| `n_components` | Component count | PCA, ICA, FactorAnalysis, LDA, gensim `LdaModel` topics |
| `n_groups` / `groups` | Grouping structure | Mixed models (`nlme` `lme`/`gls`), panel models (`plm`) |
| `n_chains` / `n_draws` | MCMC chain & sample counts | Julia `MCMCChains.Chains`, R `coda::mcmc` / `mcmc.list` |
| `n_lambda` | Regularization path length | `glmnet` / `cv.glmnet` fits |
| `n_equations` | Endogenous series count | Vector Autoregressions (VAR / VECM) |
| `order` | Lag order `[p, d, q]` | ARIMA, SARIMA, `pmdarima`, statsmodels |
| `seasonal_order` | `[P, D, Q, m]` | Seasonal ARIMA models |
| `seasonal_period` | Seasonal periods list | `ets`, `bats`/`tbats`, `nnetar`, `prophet` |
| `horizon` | Forecast horizon | `forecast(...)` results, fable forecast tables, `sktime`/`darts` forecasters |
| `changepoints` | Changepoint count | Facebook / Meta `prophet` models |
| `method` | Algorithm variant | Linkage method (`hclust`), ETS model string, test name (`htest`) |
| `target` / `formula` | Target & formula | Response variable and formula representation |
| `metrics` | Numeric fit criteria | `aic`, `bic`, `log_likelihood`, `r_squared`, `rmse`, `deviance`, `concordance` |
| `artifact_size` | File size | Serialized artifact size in bytes |

#### Examples

##### Time Series & Forecasting (R & Python)
```t
-- Fit ARIMA in Python via pmdarima or in R via forecast
p = pipeline {
    ts_node = rn(
        command = <{
            library(forecast)
            auto.arima(AirPassengers)
        }>,
        serializer = ^rds
    )
}
build_pipeline(p)

-- Inspect model facts in T instantly
info = explain(p.ts_node).foreign_meta
info.kind         -- "time_series"
info.task         -- "time_series"
info.order        -- [0, 1, 1]
info.seasonal_order -- [0, 1, 1, 12]
info.metrics.aic  -- 1017.85
```

##### Deep Learning (PyTorch, Keras, Julia Flux)
```t
-- Fit a PyTorch model in Python
p = pipeline {
    nn_node = pyn(
        command = <{
            import torch.nn as nn
            model = nn.Sequential(
                nn.Linear(20, 64),
                nn.ReLU(),
                nn.Linear(64, 1)
            )
            model
        }>,
        serializer = ^pickle
    )
}
build_pipeline(p)

-- Read parameter counts without starting Python
info = explain(p.nn_node).foreign_meta
info.kind         -- "model"
info.n_params     -- 1409
info.n_layers     -- 3
```

##### Random Forest & Gradient Boosting (ranger, XGBoost, CatBoost)
```t
-- Fit a random forest in R with ranger
p = pipeline {
    rf_node = rn(
        command = <{
            library(ranger)
            ranger(Species ~ ., data = iris, num.trees = 300)
        }>,
        serializer = ^rds
    )
}
build_pipeline(p)

info = explain(p.rf_node).foreign_meta
info.task         -- "classification"
info.n_trees      -- 300
info.n_features   -- 4
info.metrics.r_squared -- 0.94
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
3. **R/Python/Julia Runtime Loading**: Reading models via the `onnx` R package, Python `onnxruntime`, or Julia `ONNXRunTime`. Note: the R `onnx` package needs Python through `reticulate`, which T's Nix R nodes do not ship — R-side ONNX reading and scoring fails there, so use Python directly (`onnxruntime`) or T-native scoring (`t_read_onnx` plus `predict`) instead.
4. **Broader Coverage**: Neural-network and non-PMML model families that PMML cannot represent well.

Use `^pmml` when you want T's hand-written classical-model evaluator. Use `^onnx` when you want a portable model artifact with native ONNX Runtime inference in T or cross-runtime execution in Python or Julia (R nodes cannot run ONNX artifacts for the reason above). $T$ ensures that ONNX models trained in Python (Scikit-Learn) or Julia (Flux) produce consistent results when evaluated natively in $T$.

> [!NOTE]
> **Julia World Age**: When using Julia libraries that generate code at runtime (like Flux or Zygote), $T$ automatically wraps execution in `Base.invokelatest` to prevent "World Age" errors. This makes Julia nodes as robust as Python or R nodes for complex modeling tasks.

### Cross-Runtime Consistency
$T$'s statistical evaluator is verified against R's reference implementation. Results match R's `broom::tidy()` and `stats::predict()` exactly.

---

## Comparison with R's broom Package

| R (broom) / stats | T equivalent |
|-------------------|--------------|
| `broom::tidy(fit)` | `summary(model)` |
| `broom::glance(fit)` | `fit_stats(model)` |
| `broom::augment(fit, data)` | `add_diagnostics(df, model)` |
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
