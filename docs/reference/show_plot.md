# show_plot

Render a plot node and open it locally

Builds or reuses an R/Python plot artifact, renders it into `_pipeline/`, and opens the rendered image with the command configured in `tproject.toml` under `[visualization-tool]`.

## Parameters

- **plot** (`Any`): A pipeline node, built node, or `read_node()` result for a plot-producing node.


## Returns

The local rendered image path.

## See Also

[build_pipeline](build_pipeline.html), [read_node](read_node.html)

