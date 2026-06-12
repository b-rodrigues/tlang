# show_plot

Render a visualization and open it locally

Accepts a pipeline or meta-pipeline (renders the DAG as an interactive Mermaid diagram in the browser), a Mermaid diagram string (renders directly), or a plot-producing node (renders the plot artifact).

## Parameters

- **plot** (`Any`): A pipeline node, built node, `read_node()` result for a plot-producing node, a `Pipeline`/`MetaPipeline` (DAG visualization), or a Mermaid string.


## Returns

The local rendered image path for plot nodes; the Mermaid HTML path for DAG/string inputs.

## Examples

```t
show_plot(p)                       -- render pipeline as interactive Mermaid DAG
show_plot(pipeline_to_mermaid(p))  -- render Mermaid string directly
show_plot(p.my_plot_node)          -- render a plot artifact
```

## See Also

[build_pipeline](build_pipeline.html), [pipeline_to_mermaid](pipeline_to_mermaid.html), [read_node](read_node.html)

