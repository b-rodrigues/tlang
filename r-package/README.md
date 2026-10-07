# tlang R package

This companion R package provides an R `read_node()` helper for reading
artifacts from built T pipelines.

## Installation

Do not install this helper with `install.packages()`. In a T project, declare
your R dependencies in `tproject.toml`, run `t update`, and re-enter
`nix develop`; the `tlang` helper is then available from that project shell.

## Usage

By default, `read_node()` picks the reader from the build-log `serializer`
field, so JSON, CSV, IPC, and Parquet nodes load without extra arguments:

```r
library(tlang)

model <- read_node("model")      # default serializer -> readRDS()
table <- read_node("features")   # ^json -> jsonlite::read_json(), ^csv -> read.csv()
```

When a node uses `^ipc` or `^parquet` but `arrow` is not installed, the
error tells you to declare it in `tproject.toml` (`arrow` is in `Suggests`).
`jsonlite` ships in `Imports`, so `^json` always loads. `^pmml`, `^onnx`, and
`^bin` have no built-in reader: use `return_path = TRUE` plus a custom
deserializer.

Cross-language notes: `^json` simplifies vectors (`simplifyVector = TRUE`), so
arrays of records can come back as data frames, while Python and Julia return
plain dicts and lists. `^text` returns exact file bytes, matching Python and
Julia.

Pass a custom deserializer to override the automatic choice:

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

## Read a node with its children

Use `read_node_tree()` to load a node plus its transitive children (nodes
that depend on it), parents, or both. Each node keeps its own automatic
serializer unless you override it:

```r
library(tlang)

tree <- read_node_tree("clean_data")                    # clean_data + children
tree <- read_node_tree("clean_data", include = "both")  # parents + children
tree <- read_node_tree("clean_data", on_unreadable = "path")  # unreadable nodes come back as paths
```

## Inspect the pipeline

Use `inspect_pipeline()` to list every node with its runtime, serializer,
dependencies, build status, class, and artifact path. It reads the latest
build log, or falls back to `dag.json` with `status = "unbuilt"` when
nothing is built yet:

```r
tbl <- inspect_pipeline()
print(tbl)
```

Frame helpers that mirror T's pipeline tools:

```r
logs <- list_logs()                    # build logs, newest first
tbl <- build_log_to_frame()            # one row per node: name, status, duration, path
errs <- collect_exceptions()           # error and warning rows
```

Explore one node and read failures (same names as T):

```r
info <- inspect_node("model")          # runtime, deps, children, status, error, warnings
lin <- lineage("model")                # transitive parents and children
msg <- error_msg("model")              # error text, like T
msg <- warning_msg("model")            # warnings, like T
```

A single unreadable node aborts the tree by default. Use
`on_unreadable = "path"` or `"skip"` for pipelines with model artifacts
downstream. Both fallbacks warn naming the node and the error.


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
