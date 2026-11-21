# explain

Explain Value

Returns a dictionary describing the structure and content of a value. 

For primitive types, collections, and DataFrames, `explain()` provides structural summaries: data dimensions, schema columns, NA counts, and example rows. 

For pipeline node results from `read_node(...)`, `explain()` returns a node wrapper with `kind`, `node_name`, `diagnostics`, and the explained payload under `contents`. 

For computed pipeline nodes (e.g. `explain(p.node)`), `explain()` exposes the zero-cost build-time `foreign_meta` sidecar dictionary recorded during Nix derivation execution for R, Python, and Julia nodes, avoiding deserialization or initializing foreign runtimes. 

Supported `foreign_meta` fields include: 

- `kind`: Value kind ("dataframe", "matrix", "vector", "array", "factor", "series", "table", "model", "test", "data", "transformer", "distribution", "forecast", "chain", "dist", "graph", "dataset", "image", "optimization", "ode", "other", or "unknown") 
- `class`: Runtime type name (e.g. "lm", "DataFrame", "ARIMA", "SimpleGraph") 
- `task`: Model task ("regression", "classification", "clustering", "time_series", "dim_reduction", "density", "anomaly_detection", "ranking", "survival") 
- `dimensions`: Shape as an integer list, e.g. [32, 11] for frames, [4, 3] for matrices 
- `n_obs`: Training row count 
- `n_features`: Number of features or predictor columns 
- `n_groups`, `groups`: Grouping counts for mixed-effects and panel models (e.g. `nlme` `lme`/`gls`) 
- `n_trees`, `n_rounds`: Tree count and boosting rounds (e.g. Random Forest, XGBoost, CatBoost, gbm) 
- `n_clusters`: Cluster count (e.g. k-means, Mclust, dbscan, Clustering.jl) 
- `n_nodes`, `n_edges`: Graph vertex and edge counts (igraph, networkx, Graphs.jl) or decision tree nodes (`rpart`, `BinaryTree`) 
- `n_components`: Dimensionality reduction components (PCA, ICA, FactorAnalysis, LDA) 
- `n_params`, `n_layers`: Parameter and layer counts (PyTorch, Keras, Flux, neuralnet, R6 torch/keras) 
- `n_chains`, `n_draws`: MCMC chain and draw counts (Julia `Chains`, coda `mcmc`/`mcmc.list`) 
- `n_lambda`: Regularization path length (`glmnet`, `cv.glmnet`) 
- `n_equations`: Endogenous series count for VAR/VECM models 
- `dtype`: Element data type (e.g. "float64") 
- `n_levels`, `levels`: Categorical level counts and values (R factors, Julia `CategoricalArray`) 
- `start`, `end`: Time-series bounds (R `ts`, `zoo`/`xts`) 
- `order`, `seasonal_order`, `seasonal_period`: Time-series specifications (ARIMA, SARIMA, ETS, BATS/TBATS, Prophet, NNETAR, pmdarima) 
- `horizon`: Forecast horizon (forecast results, fable, sktime, darts, statsforecast) 
- `changepoints`: Changepoint counts (Prophet) 
- `method`: Algorithm variant, linkage method, ETS letters, or test name 
- `target`, `formula`: Response variable and model formula 
- `metrics`: Free numeric metrics (e.g. AIC, BIC, log-likelihood, R-squared, RMSE, deviance) 
- `artifact_size`: Materialized artifact size in bytes 

Explaining a pipeline (`explain(p)`) lists per-node `dependencies` (direct inputs) and `children` (direct dependents) plus the transitive `ancestors` and `descendants` closures (nearest-first, de-duplicated).

## Parameters

- **x** (`Any`): The value to explain.


## Returns

A structured description of the value.

## Examples

```t
explain(mtcars)
explain(p.fit).foreign_meta
explain(p.forecast_node).foreign_meta.horizon
explain(p.nn_model).foreign_meta.n_params
explain(p)
```

## See Also

[str](str.html), [type](type.html)

