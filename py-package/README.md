# tlang Python package

This companion Python package provides a Python `read_node()` helper for reading
artifacts from built T pipelines.

## Installation

Do not install this helper with `pip`. In a T project, declare your Python
dependencies in `tproject.toml`, run `t update`, and re-enter `nix develop`;
the `tlang` helper is then available from that project shell.

## Usage

By default, `read_node()` picks the reader from the build-log `serializer`
field, so JSON, CSV, IPC, and Parquet nodes load without extra arguments:

```python
from tlang import read_node

model = read_node("model")    # default serializer -> pickle
table = read_node("features") # ^json -> json.load, ^csv -> pandas.read_csv
```

When a node uses `^json` but the reader fails, the error names the expected
reader. When `^csv`, `^ipc`, or `^parquet` need `pandas`/`pyarrow`, the error
tells you to declare them in `tproject.toml`. `^pmml`, `^onnx`, and `^bin` have
no built-in reader: use `return_path=True` plus a custom deserializer.

Cross-language notes: `^json` returns plain dicts and lists, while R
simplifies vectors. `^text` returns exact file bytes, matching Julia and R.

Pass a custom deserializer to override the automatic choice:

```python
import pyarrow.ipc as ipc
from tlang import read_node

table = read_node("features", deserializer=lambda path: ipc.open_file(path).read_all())
```

You can also target a specific historical build log:

```python
older_model = read_node("model", which_log="20260221")
```

## Read a node with its children

Use `read_node_tree()` to load a node plus its transitive children (nodes
that depend on it), parents, or both. Each node keeps its own automatic
serializer unless you override it:

```python
from tlang import read_node_tree

all_nodes = read_node_tree("clean_data")                    # clean_data + children
all_nodes = read_node_tree("clean_data", include="both")    # parents + children
all_nodes = read_node_tree("clean_data", on_unreadable="path")  # unreadable nodes come back as paths
```

## Inspect the pipeline

Use `inspect_pipeline()` to list every node with its runtime, serializer,
dependencies, build status, class, and artifact path. It reads the latest
build log, or falls back to `dag.json` with `status = "unbuilt"` when
nothing is built yet:

```python
rows = tlang.inspect_pipeline()
print(rows)
```

Frame helpers that mirror T's pipeline tools:

```python
logs = tlang.list_logs()  # build logs, newest first
rows = tlang.build_log_to_frame()  # one row per node: name, status, duration, path
errs = tlang.collect_exceptions()  # error and warning rows
```

Explore one node and read failures (same names as T):

```python
info = tlang.inspect_node("model")  # runtime, deps, children, status, error, warnings
lin = tlang.lineage("model")  # transitive parents and children
msg = tlang.error_msg("model")  # error text, like T (raises TypeError when healthy)
msg = tlang.warning_msg("model")  # warnings, like T
```

A single unreadable node aborts the tree by default. Use
`on_unreadable="path"` or `"skip"` for pipelines with model artifacts
downstream. Both fallbacks warn naming the node and the error.

## Diff Python artifacts

Use the bundled unified-diff helpers to compare Python-native artifacts that do
not have a direct T equivalent, such as pickled model objects or custom classes:

```python
from tlang import diff_nodes

diff = diff_nodes("weights", "weights", which_log_a="20260501", which_log_b="latest")
print(diff["kind"])
print(diff["summary"])
```


## Inspect pipeline DAG

Get the nodes and their dependencies as a dictionary:

```python
import tlang

nodes = tlang.pipeline_nodes()
print(nodes)
```
