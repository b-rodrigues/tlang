# tlang R package

This companion R package provides an R `read_node()` helper for reading
artifacts from built T pipelines.

## Installation

From the repository root:

```r
install.packages("r-package", repos = NULL, type = "source")
```

## Usage

By default, `read_node()` uses `readRDS()`:

```r
library(tlang)

model <- read_node("model")
```

Pass a custom deserializer when a node uses another artifact format:

```r
table <- read_node(
  "features",
  deserializer = arrow::read_ipc_file
)
```

You can also target a specific historical build log:

```r
older_model <- read_node("model", which_log = "20260221")
```


## Inspect pipeline DAG

Render `_pipeline/dag.json` as a tree:

```r
cat(pipeline_nodes(), sep = "\n")
```
