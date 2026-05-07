# Weighted Calculation Support: `weight` Argument Design

This document specifies which statistical functions in the standard library should
accept an optional `weight` argument, and the rationale behind each decision.

The guiding principle is: **does weighting change the estimand, or just the
computation?** For descriptive statistics and model fitting, the weighted and
unweighted versions estimate fundamentally different quantities (e.g. a
population mean vs. a sample mean). For transformations, extrema, and
model-interrogation functions, weighting does not apply at the call site.


## Definite yes

These functions have well-established weighted variants used routinely in
survey analysis, sample-weighted epidemiology, and panel econometrics. Their
signatures should all accept `weight = null` as an optional argument.

| Function | Weighted variant | Notes |
|---|---|---|
| `mean(x)` | Weighted mean | Foundational; most other weighted estimators derive from it |
| `sd(x)` | Weighted standard deviation | Follows from weighted variance |
| `var(x)` | Weighted variance | Standard formula: $\sum w_i (x_i - \bar{x}_w)^2 / \sum w_i$ |
| `median(x)` | Weighted median | Standard in survey statistics; minimises weighted absolute deviation |
| `quantile(x, p)` | Weighted quantile | Underpins `iqr`, `fivenum`, `trimmed_mean`, `winsorize` — see below |
| `cov(x, y)` | Weighted covariance | Essential for survey-weighted regression and PCA |
| `cor(x, y)` | Weighted correlation | Derived from weighted covariance and variance |
| `lm(data, formula)` | Weighted least squares (WLS) | Primary use case; weights are observation-level |
| `skewness(x)` | Weighted skewness | Weighted third central moment over weighted variance |
| `kurtosis(x)` | Weighted excess kurtosis | Weighted fourth central moment |
| `cv(x)` | Weighted coefficient of variation | Derived from weighted `sd` / weighted `mean`; must be consistent |


## Yes, via weighted quantiles

These functions are defined in terms of `quantile` internally. If `quantile`
accepts weights, these must too — otherwise the library would be internally
inconsistent and users could not obtain coherent weighted summaries.

| Function | Dependency | Notes |
|---|---|---|
| `iqr(x)` | `quantile(x, 0.75) − quantile(x, 0.25)` | Pass weights through to both quantile calls |
| `fivenum(x)` | Five calls to `quantile` | Same delegation pattern |
| `trimmed_mean(x, trim)` | Trim points are quantile-defined | Weights change which observations are trimmed |
| `winsorize(x, limits)` | Cap points are quantile-defined | Weights change where the caps fall |


## No

Weights are either structurally inapplicable or already handled elsewhere.

### Extrema and order statistics

`min`, `max`, and `range` are order statistics: they return the smallest or
largest observed value regardless of how many times that value is
"represented." Weights cannot move the extremes of the support, so adding a
`weight` argument would be misleading.

### `mode`

Frequency is already the implicit weight in mode estimation. Accepting a
separate `weight` argument would conflate two different things (observed count
vs. analytic weight) and the semantics become ambiguous. Leave it out.

### `mad`

Weighted MAD exists in the literature but the definition is contested — it is
unclear whether to weight the inner median, the outer median, or both. Given
the lack of a canonical formula and the niche use case, omit for now and
revisit if demand arises.

### `huber_loss`

Observation-level weights in a loss function are an optimisation-layer
concern, not a descriptive-statistics concern. If the user needs a weighted
robust loss, that belongs in the model-fitting API (e.g. as an argument to
`lm`), not on the standalone `huber_loss` utility.

### Transformation functions

`scale` / `standardize` and `normalize` are transformations derived from the
descriptive statistics above. If the user needs weighted standardisation, they
should compose:

```
scale(x, mean = mean(x, weight = w), sd = sd(x, weight = w))
```

Folding weights into the transformation itself obscures what is happening and
makes the function harder to reason about.

### Model-interrogation functions

`predict`, `anova`, `summary`, `fit_stats`, `add_diagnostics` all operate on
a model object. Weights are part of the model specification and were already
supplied to `lm` (or equivalent) at fit time. Repeating them at the
interrogation call site would be redundant and error-prone.

### Distribution CDFs

`pnorm`, `pt`, `pf`, `pchisq` are mathematical functions of their arguments.
They have no concept of a data sample, so weighting does not apply.

### Structural / IO functions

`poly`, `cut`, `read_onnx`, `read_pmml` are either structural transformations
or IO operations. Weighting is not meaningful in any of these contexts.


## Summary table

| Function | `weight`? | Reason |
|---|:---:|---|
| `mean(x)` | ✓ | Foundational weighted estimator |
| `sd(x)` | ✓ | Weighted variance |
| `var(x)` | ✓ | Weighted variance |
| `median(x)` | ✓ | Weighted median |
| `quantile(x, p)` | ✓ | Weighted quantile |
| `cov(x, y)` | ✓ | Weighted covariance |
| `cor(x, y)` | ✓ | Derived from weighted cov/var |
| `lm(data, formula)` | ✓ | WLS |
| `skewness(x)` | ✓ | Weighted moments |
| `kurtosis(x)` | ✓ | Weighted moments |
| `cv(x)` | ✓ | Derived from weighted mean/sd |
| `iqr(x)` | ✓ | Via weighted quantile |
| `fivenum(x)` | ✓ | Via weighted quantile |
| `trimmed_mean(x, trim)` | ✓ | Via weighted quantile |
| `winsorize(x, limits)` | ✓ | Via weighted quantile |
| `min(x)` | ✗ | Order statistic; weights cannot move extremes |
| `max(x)` | ✗ | Order statistic |
| `range(x)` | ✗ | Order statistic |
| `mode(x)` | ✗ | Frequency is already the implicit weight |
| `mad(x)` | ✗ | No canonical weighted definition |
| `huber_loss(x, delta)` | ✗ | Optimisation-layer concern, not descriptive stats |
| `scale(x)` / `standardize(x)` | ✗ | Compose from weighted mean/sd instead |
| `normalize(x)` | ✗ | Min-max; extrema are weight-invariant |
| `predict(data, model)` | ✗ | Weights live in the model object |
| `anova(m1, m2)` | ✗ | Weights live in the model object |
| `summary(model)` | ✗ | Weights live in the model object |
| `fit_stats(model)` | ✗ | Weights live in the model object |
| `add_diagnostics(model, data)` | ✗ | Weights live in the model object |
| `pnorm` / `pt` / `pf` / `pchisq` | ✗ | Mathematical functions, no sample |
| `poly(x, degree)` | ✗ | Structural transformation |
| `cut(x, breaks)` | ✗ | Structural transformation |
| `read_onnx(path)` | ✗ | IO |
| `read_pmml(path)` | ✗ | IO |
