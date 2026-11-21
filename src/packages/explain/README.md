# explain

Value introspection and intent blocks.

## Functions

| Function | Description |
|----------|-------------|
| `explain(x)` | Return a dict describing a value's type, structure, and metadata |
| `explain_json(x)` | Return the explanation as a JSON string |
| `intent_fields(i)` | Get the field names from an intent block |
| `intent_get(i, key)` | Get a specific field value from an intent block |

## Intent Blocks

Intent blocks attach metadata to values:

```t
result = data |> summarize(total = sum($amount))

why = intent {
  goal = "Calculate total sales"
  method = "Sum of amount column"
  source = "sales.csv"
}

intent_fields(why)         -- ["goal", "method", "source"]
intent_get(why, "goal")    -- "Calculate total sales"
```

## Examples

```t
explain(42)           -- {type: "Int", value: "42"}
explain([1, 2, 3])    -- {type: "List", length: 3, ...}
explain_json(42)      -- JSON string
```

## Foreign Node Metadata

Computed pipeline nodes (`p.node`) from R, Python, and Julia runtimes carry
a `foreign_meta` dict, populated at build time into a `meta` sidecar file
next to `artifact`/`class` (best effort — the build never fails for it):

```t
e = explain(p.fit)
e.foreign_meta.kind        -- value kind: "dataframe", "matrix", "vector", "array", "factor", "series", "table", "model", "test", "data", "transformer", "distribution", "forecast", "chain", "dist", "graph", "dataset", "image", "optimization", "ode", "other", or "unknown"
e.foreign_meta.class        -- runtime type name, e.g. "lm", "DataFrame", "ARIMA"
e.foreign_meta.task         -- model task when known: "regression", "classification", "clustering", "time_series", "dim_reduction", "density", "anomaly_detection", "ranking", or "survival"
e.foreign_meta.dimensions  -- shape as int list, e.g. [32, 11] for frames, [4, 3] for matrices, [3] for vectors
e.foreign_meta.n_obs       -- training rows (models)
e.foreign_meta.n_groups    -- grouping units, e.g. 18 subjects (mixed models)
e.foreign_meta.groups      -- per-group counts, e.g. {Subject: 18} (mixed models)
e.foreign_meta.n_features  -- input count (models)
e.foreign_meta.n_trees     -- tree count (forests, when known)
e.foreign_meta.n_rounds    -- boosting rounds (boosted trees, when known)
e.foreign_meta.n_clusters  -- cluster count (clustering, when known)
e.foreign_meta.n_nodes      -- tree node count (`rpart`, `party::BinaryTree`, `partykit::ctree`, when known)
e.foreign_meta.n_edges      -- edge count (igraph / networkx / Graphs.jl graphs, when known)
e.foreign_meta.n_components -- component count (PCA, ICA, FactorAnalysis, LDA, when known)
e.foreign_meta.n_params     -- total parameter count (torch/keras/Flux/HuggingFace models, MCMC variables, GARCH estimates, when known)
e.foreign_meta.n_layers    -- layer count (torch leaf layers, keras/Flux models, when known)
e.foreign_meta.n_chains    -- MCMC chain count (Julia `Chains`, coda `mcmc.list`, when known)
e.foreign_meta.n_draws     -- draws per chain (Julia `Chains`, coda `mcmc`, when known)
e.foreign_meta.n_lambda    -- lambda count (`glmnet` fits, when known)
e.foreign_meta.n_equations -- endogenous series count (VAR/VECM, when known)
e.foreign_meta.dtype        -- element type, e.g. "float64" (arrays, when known)
e.foreign_meta.n_levels     -- level count with levels list (R factors, Julia `CategoricalArray`)
e.foreign_meta.start        -- series start, e.g. "1949-1" (R ts, zoo/xts)
e.foreign_meta.end          -- series end, e.g. "1960-12" (R ts, zoo/xts)
e.foreign_meta.method      -- algorithm variant: hclust linkage, ETS letters, VAR/boosting loss names, or the test name for `htest` results
e.foreign_meta.target      -- response name (when known)
e.foreign_meta.formula     -- full formula (R models, when known)
e.foreign_meta.order       -- [p, d, q] (time-series models, when known)
e.foreign_meta.seasonal_order -- [P, D, Q, m] (seasonal models, when known)
e.foreign_meta.seasonal_period -- seasonal period list (`ets`, `bats`/`tbats`, `nnetar`, `prophet`, when known)
e.foreign_meta.horizon     -- forecast horizon (forecast results, fable tables, sktime/statsforecast forecasters, when known)
e.foreign_meta.changepoints -- changepoint count (prophet, when known)
e.foreign_meta.features    -- full feature/column list (first 500 entries; `n_features` stays exact)
e.foreign_meta.metrics     -- free numeric metrics (r_squared, aic, bic, loglik, ...); numbers only, other values are dropped
e.foreign_meta.artifact_size -- artifact size in bytes
```

`features`/`n_features` meaning varies by family: input variable names
for frames, forests, and discriminant means; fitted coefficient names
for `lm`-family models. `seasonal_order` is only emitted for genuinely
seasonal fits. Metrics are best effort per runtime and differ by family;
check presence before use.

Supported ecosystems and families:

- **Time series & forecasting**: R `ets`/`bats`/`tbats`/`nnetar`/
  `prophet`/`garch`/`uGARCHfit`/`varest`/`vec2var`/`smooth`/`dlmFiltered`,
  tidyverts `fable` (`forecast` kind with horizon) and `mable` (`mdl_df`/
  `model_df`), `forecast(...)` results, and `zoo`/`xts` (`series` kind
  with start/end); Python `pmdarima`/`tbats`/`skforecast`/`sktime`/
  `statsforecast`/`neuralprophet`, `darts` (`input_chunk_length`/
  `output_chunk_length` in metrics), and statsmodels `VECM`/Markov-regime;
  Julia `ARCHModels`.
- **ML, mixed, & regularized models**: R `mgcv::gam`/`bam`, `nlme`
  `lme`/`gls`, `glmnet`/`cv.glmnet`, `ranger`, `catboost.Model`, `rq`,
  `survreg`, `betareg`, `zeroinfl`/`hurdle`, `plm`, `clm`/`clmm`, VGAM
  `vglm`, `caret::train` (with `r_squared`), `parsnip` `model_fit`/
  `workflows::workflow`, `e1071::svm`, `kernlab::ksvm`, `gbm`, `C5.0`,
  `earth`, `pls::mvr`, `rpart`, `party::BinaryTree`, `partykit::ctree`,
  `neuralnet`; Python `scikit-learn`/`imblearn`, `catboost`, `pyspark.ml`,
  `tslearn`; Julia `MLJ` machines and `XGBoost.jl` boosters.
- **Deep learning**: Python `torch`/`keras`, HuggingFace `transformers`
  models (`transformer` kind for tokenizers/pipelines), R6 `keras`/`torch`
  modules, and Julia `Flux` models (`n_params`, `n_layers`).
- **Clustering, ordination, tests, chains, & structures**: R `Mclust`,
  `dbscan`, `clara`/`fanny`, `mixEM`, FactoMineR `PCA`/`MCA`/`FAMD`/`CA`
  (0–1 `var_first`), `psych` `fa`/`principal`, `urca` (`test` kind),
  `coda` (`chain` kind), `lavaan`, `dist` (`dist` kind), sparse `Matrix`,
  `igraph` (`graph` kind, `n_edges`), `Seurat` (`dataset` kind); Python
  `gensim`, `dask` frames, `xarray` `Dataset`, `PIL` images (`image`
  kind), `networkx` (`graph` kind); Julia `Distributions`, `MCMCChains`,
  `CategoricalArray` (`factor` kind), `Clustering.jl` `CmeansResult`/
  `DbscanResult`/`KmedoidsResult`, `MultivariateStats` (`dim_reduction`),
  `Graphs.jl` (`graph` kind), `JuMP` (`optimization` kind), `SciML` ODEs
  (`ode` kind), and `GaussianMixtures` (`density`).

The tree display shows short `features_preview`/`formula_preview` forms;
dot access on `features`/`formula` returns the full values. Unbuilt nodes
report `foreign_meta` as `NA`.

## Status

Built-in package — included with T by default.
