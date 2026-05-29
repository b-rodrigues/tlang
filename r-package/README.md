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


## Diff R artifacts

Use the bundled diffobj-based helpers to compare R-native artifacts such as
models, lists, or custom S3 objects:

```r
library(tlang)

diff <- diff_nodes("model", "model", which_log_a = "20260501", which_log_b = "latest")
print(diff$kind)
print(diff$summary)
```


## Inspect pipeline DAG

Get the nodes and their dependencies as a data frame:

```r
nodes <- pipeline_nodes()
print(nodes)
```
