# tlang Julia package

This companion Julia package provides a Julia `read_node()` helper for reading
artifacts from built T pipelines, plus DeepDiffs-based helpers for comparing
Julia-native node artifacts.

## Installation

Do not install this helper with `Pkg.add()` or `Pkg.develop()`. In a T project,
declare your Julia dependencies in `tproject.toml`, run `t update`, and
re-enter `nix develop`; the `tlang` helper is then available from that project
shell.

## Usage

By default, `read_node()` picks the reader from the build-log `serializer`
field, so JSON, CSV, IPC, Parquet, and text nodes load without extra arguments:

```julia
using tlang

model = read_node("model")    # default serializer -> Serialization.deserialize
table = read_node("features") # ^json -> JSON.parsefile, ^csv -> CSV.read
```

`JSON` ships with the package, so `^json` always parses to plain dicts and
lists. When a node uses `^csv` without `CSV`/`DataFrames`, the error names the
packages and the `tproject.toml` entries. The same holds for `^ipc` (`Arrow`,
`DataFrames`) and `^parquet` (`Parquet2`, `DataFrames`). `^pmml`, `^onnx`, and
`^bin` have no built-in reader: use `return_path = true` plus a custom
deserializer.

Cross-language notes: `^text` returns exact file bytes, matching Python and R.

Pass a custom deserializer to override the automatic choice:

```julia
using tlang, DataFrames, CSV

table = read_node("features", deserializer = p -> CSV.read(p, DataFrame))
```

You can also target a specific historical build log:

```julia
older_model = read_node("model", which_log = "20260221")
```

## Read a node with its children

Use `read_node_tree()` to load a node plus its transitive children (nodes
that depend on it), parents, or both. Each node keeps its own automatic
serializer unless you override it:

```julia
using tlang

all_nodes = read_node_tree("clean_data")                  # clean_data + children
all_nodes = read_node_tree("clean_data", include = "both") # parents + children
all_nodes = read_node_tree("clean_data", on_unreadable = "path") # unreadable nodes come back as paths
```

## Inspect the pipeline

Use `inspect_pipeline()` to list every node with its runtime, serializer,
dependencies, build status, class, and artifact path. It reads the latest
build log, or falls back to `dag.json` with `status = "unbuilt"` when
nothing is built yet:

```julia
rows = inspect_pipeline()
println(rows)
```

Frame helpers that mirror T's pipeline tools:

```julia
logs = list_logs()  # build logs, newest first
rows = build_log_to_frame()  # one row per node: name, status, duration, path
errs = collect_exceptions()  # error and warning rows
```

Explore one node and read failures (same names as T):

```julia
info = inspect_node("model")  # runtime, deps, children, status, error, warnings
lin = lineage("model")  # transitive parents and children
msg = error_msg("model")  # error text, like T
msg = warning_msg("model")  # warnings, like T
println(show_code("model"))  # node source for copy-paste tweaking
println(show_code("model", verify = true))  # also check the script hash
```

A single unreadable node aborts the tree by default. Use
`on_unreadable = "path"` or `"skip"` for pipelines with model artifacts
downstream. Both fallbacks warn naming the node and the error.

## Diff Julia artifacts

Use the bundled DeepDiffs-based helpers to compare Julia-native artifacts that
do not have a direct T equivalent:

```julia
using tlang

diff = diff_nodes("weights", "weights", which_log_a = "20260501", which_log_b = "latest")
println(diff["kind"])
println(diff["summary"])
```

## Inspect pipeline DAG

Get the nodes and their dependencies as a `Dict`:

```julia
using tlang

nodes = pipeline_nodes()
println(nodes)
```
