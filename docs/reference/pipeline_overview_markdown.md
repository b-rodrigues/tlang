# pipeline_overview_markdown

Markdown overview table

Same rows as pipeline_overview, rendered as a Markdown table for reports and workflow summaries.

## Parameters

- **pipeline** (`Pipeline`): The pipeline to summarize.

- **only** (`String`): = NA Same filter as pipeline_overview.


## Returns

Markdown table with name, runtime, status, depth, error.

## Examples

```t
pipeline_overview_markdown(p)
pipeline_overview_markdown(p, only = "failed")
```

## See Also

[pipeline_report](pipeline_report.html), [pipeline_overview](pipeline_overview.html)

