# External Helper Packages (R, Python, Julia)

To facilitate the consumption of T-Lang build artifacts from within other languages, we provide lightweight helper packages for **R**, **Python**, and **Julia**. All these packages are named **`tlang`** in their respective ecosystems. These packages allow you to easily locate and read built nodes from a T pipeline without manually parsing build logs or resolving Nix store paths.

## Automatic Availability

These packages are **automatically installed and loaded** in every R, Python, and Julia node in a T pipeline. You do not need to install them manually. The `read_node()` function and its dependencies are ready to use immediately.

For project development shells, `t update` also wires the matching companion package into `flake.nix` whenever you declare dependencies in `[r-dependencies]`, `[py-dependencies]`, or `[jl-dependencies]`, so the helper is available from `nix develop` as well.

## Key Features

- **`read_node(name)`**: Automatically locates the latest build log in the `_pipeline/` directory, finds the requested node, and deserializes its artifact.
- **`read_node_tree(name)`**: Reads a node plus its transitive children, parents, or both from the single selected build log.
- **`inspect_pipeline()`**: Returns every node with its runtime, serializer, dependencies, build status, class, and artifact path (falls back to `dag.json` with `status = "unbuilt"` when nothing is built yet).
- **`list_logs()`**: Lists build logs newest-first with filename, modification time, size, and pipeline name.
- **`build_log_to_frame()`**: Tabulates one build log as per-node rows (`name`, `status`, `duration`, `path`).
- **`collect_exceptions()`**: Gathers error and warning rows (`node`, `status`, `code`, `message`) from one build log.
- **`inspect_node(name)`**: Inspects one node: runtime, serializer, dependencies, children, status, error, and warnings.
- **`lineage(name)`**: Lists transitive parents and children (names only, nearest first).
- **`error_msg(name)`, `error_code(name)`, `error_context(name)`**: Same names as T. Return a failed node's message, code, or context dict. Foreign-runtime failures are VError JSON, so an R error reads the same from Python or Julia. Stop when the node is healthy, like T.
- **`warning_msg(name)`**: Same name as T. Returns formatted warnings (`""` when none), with upstream warnings prefixed by source.
- **`pipeline_nodes()`**: Returns the pipeline DAG (nodes and their dependencies) as an idiomatic data structure (data frame in R, dictionary in Python/Julia).
- **Support for historical logs**: Use the `which_log` argument to select a specific build log using a regular expression.
- **Custom Deserializers**: Pass a custom function to handle specific artifact formats.
- **`return_path` support**: If you only need the absolute path to the artifact (e.g., to pass to a specialized loader), set `return_path = true`.

---

## R: `tlang`

The R package is automatically loaded in all R nodes.

### Usage

```r
# read_node is available by default
# library(tlang) is called automatically

# Read the latest 'my_data' node
df <- read_node("my_data")

# Get only the path to the artifact
path <- read_node("my_model", return_path = TRUE)

# Inspect the pipeline DAG (returns a data.frame)
nodes <- pipeline_nodes()

# Inspect nodes with their latest build status
tbl <- inspect_pipeline()
```

---

## Python: `tlang`

The Python package is automatically imported in all Python nodes.

### Usage

```python
# read_node is available by default
# import tlang is called automatically

# Read the latest 'my_data' node
df = tlang.read_node("my_data")

# Get only the path to the artifact
path = tlang.read_node("my_model", return_path=True)

# Inspect the pipeline DAG (returns a dict)
nodes = tlang.pipeline_nodes()

# Inspect nodes with their latest build status
rows = tlang.inspect_pipeline()
```

---

## Julia: `tlang`

The Julia package is automatically loaded with `using tlang` in all Julia nodes.

### Usage

```julia
# read_node is available by default
# using tlang is called automatically

# Read the latest 'my_data' node
df = read_node("my_data")

# Get only the path to the artifact
path = read_node("my_model", return_path=true)

# Compare Julia-native artifacts across historical builds
diff = diff_nodes("my_model", "my_model", which_log_a="20260501", which_log_b="latest")

# Inspect the pipeline DAG (returns a Dict)
nodes = pipeline_nodes()

# Inspect nodes with their latest build status
rows = inspect_pipeline()
```

---

## How it Works

When you run `build_pipeline()`, T-Lang generates a timestamped build log (e.g., `_pipeline/build_log_20260514_160236.json`). These helper packages:

1.  Scan the `_pipeline/` directory for `build_log_*.json` files.
2.  Sort them reverse-alphabetically to find the most recent one.
3.  Parse the JSON to find the entry for the requested node.
4.  Resolve the `path` (which might be relative to the project root or an absolute Nix store path).
5.  Call the appropriate deserializer (`readRDS` for R, `pickle.load` for Python, `Serialization.deserialize` for Julia).

When T's `node_diff()` delegates to these helpers for runtime-native object
comparisons, it preserves the original native artifact only for nodes using the
standard `default` or `tobj` serializers. If you use a custom serializer name,
call the helper package directly and pass the matching deserializer yourself.
Julia-native diffs invoked from T currently launch a fresh Julia helper process
for each comparison, so repeated large diffs will include Julia startup cost.
