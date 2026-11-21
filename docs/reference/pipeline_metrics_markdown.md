# pipeline_metrics_markdown

Markdown Model Metrics Leaderboard

Renders model metadata and metrics (`name`, `runtime`, `kind`, `task`, `method`, `n_obs`, `status`, plus all metric columns) as a Markdown table for reports and workflow summaries.

## Parameters

- **pipeline** (`Pipeline`): The pipeline to compare.

- **task** (`String`): = NA Optional task filter.

- **sort_by** (`String`): = NA Optional column to sort by.

- **descending** (`Bool`): = false Sort descending when true.


## Returns

Markdown table of model metadata and metrics.

## Examples

```t
pipeline_metrics_markdown(p)
pipeline_metrics_markdown(p, sort_by = "aic")
```

## See Also

[pipeline_report](pipeline_report.html), [pipeline_overview_markdown](pipeline_overview_markdown.html), [pipeline_metrics](pipeline_metrics.html)

