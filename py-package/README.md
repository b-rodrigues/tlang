# tlang Python package

This companion Python package provides a Python `read_node()` helper for reading
artifacts from built T pipelines.

## Installation

From the repository root:

```bash
pip install ./py-package
```

## Usage

By default, `read_node()` uses Python object deserialization with `pickle`,
falling back to `dill` and `cloudpickle` when available:

```python
from tlang import read_node

model = read_node("model")
```

Pass a custom deserializer when a node uses another artifact format:

```python
import pyarrow.ipc as ipc
from tlang import read_node

table = read_node("features", deserializer=lambda path: ipc.open_file(path).read_all())
```

You can also target a specific historical build log:

```python
older_model = read_node("model", which_log="20260221")
```


## Inspect pipeline DAG

Render `_pipeline/dag.json` as a tree:

```python
from tlang import pipeline_nodes

print(pipeline_nodes())
```
