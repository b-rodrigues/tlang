# pipeline_metrics

Cross-Runtime Model Metrics Leaderboard

Collects build-time `foreign_meta` sidecars from model nodes across R, Python, and Julia into a single comparison DataFrame. Includes every built node whose `meta` sidecar reports `kind = "model"` or non-empty `metrics`. Base columns (`name`, `runtime`, `kind`, `task`, `method`, `n_obs`, `n_features`, `status`) are followed by one Float column per metric key found across the selected nodes (sorted alphabetically, NA where a node does not report that metric). Metric keys that collide with a base column name are prefixed with `metric_`. Non-finite metrics (NaN/Inf) are recorded as NA, and nodes with missing or unreadable `meta` sidecars are skipped.

## Parameters

- **pipeline** (`Pipeline`): The pipeline to compare.

- **task** (`String`): = NA Optional task filter (e.g. "regression", "classification", "time_series").

- **sort_by** (`String`): = NA Optional column to sort by (any metric column, "n_obs", "n_features", or "name").

- **descending** (`Bool`): = false Sort descending when true (default false, lowest metric first).


## Returns

One row per model node with aligned metric columns.

## Examples

```t
pipeline_metrics(p)
pipeline_metrics(p, task = "time_series", sort_by = "aic")
pipeline_metrics(p, sort_by = "r2", descending = true)
```

## See Also

[explain](explain.html), [pipeline_overview](pipeline_overview.html), [pipeline_metrics_markdown](pipeline_metrics_markdown.html)

