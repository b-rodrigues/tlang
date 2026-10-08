# External Helper Packages (R, Python, Julia)

To facilitate the consumption of T-Lang build artifacts from within other languages, we provide lightweight helper packages for **R**, **Python**, and **Julia**. All these packages are named **`tlang`** in their respective ecosystems. These packages allow you to easily locate and read built nodes from a T pipeline without manually parsing build logs or resolving Nix store paths.

## Automatic Availability

These packages are **automatically installed and loaded** in every R, Python, and Julia node in a T pipeline. You do not need to install them manually. The `read_node()` function and its dependencies are ready to use immediately.

For project development shells, `t update` also wires the matching companion package into `flake.nix` whenever you declare dependencies in `[r-dependencies]`, `[py-dependencies]`, or `[jl-dependencies]`, so the helper is available from `nix develop` as well.

## Key Features

### Reading values

- **`read_node(name)`**: Automatically locates the latest build log in the `_pipeline/` directory, finds the requested node, and deserializes its artifact. When `deserializer` is not passed, the `serializer` field from the build log picks the reader (see the table below). Pass a function to override. Failing native reads name the building runtime when it differs, so an RDS file read from Python points at `return_path` instead of a raw pickle traceback.
- **`read_node_tree(name)`**: Reads a node plus its transitive children, parents, or both from the single selected build log, so a concurrent build cannot mix two snapshots. Each node keeps its own automatic serializer unless `deserializer` overrides it for all of them. With `on_unreadable = "path"`, an unreadable node maps to a path/serializer record, so the caller can recover manually.

### Reading code

- **`show_code(name)`**: Returns a node's source for copy-paste tweaking. Foreign code comes back verbatim; T expressions come back as normalized T source. Exterior `script =` nodes return the script path. Note: only the path is stored for scripts, so the file may differ from what was built; pass the `verify` flag to check the recorded content hash. Embedded secrets land in the build log under `_pipeline/`, which is easier to share by accident than a store path; set `[pipeline].record_source = false` in `tproject.toml` to keep embedded code out of logs.

### Inspecting structure and status

- **`inspect_pipeline()`**: Returns every node with its runtime, serializer, dependencies, build status, class, and artifact path (falls back to `dag.json` with `status = "unbuilt"` when nothing is built yet).
- **`pipeline_nodes()`**: Returns the pipeline DAG (nodes and their dependencies) as an idiomatic data structure (data frame in R, dictionary in Python/Julia).
- **`inspect_node(name)`**: Inspects one node without loading its value: runtime, serializer, dependencies, direct children, status, class, path, error record, and warnings.
- **`lineage(name)`**: Lists transitive parents and children (names only, nearest first, sorted within each level).

### Failures and warnings

- **`error_msg(name)`, `error_code(name)`, `error_context(name)`**: Same names as T. Return a failed node's message, code, or context dict. Foreign-runtime failures are VError JSON, so an R error reads the same from Python or Julia. Stop when the node is healthy, like T.
- **`warning_msg(name)`**: Same name as T. Returns formatted warnings (`""` when none), with upstream warnings prefixed by source.
- **`collect_exceptions()`**: Gathers error and warning rows (`node`, `status`, `code`, `message`) from one build log.

### Build history

- **`list_logs()`**: Lists build logs newest-first with filename, modification time, size, and pipeline name.
- **`build_log_to_frame()`**: Tabulates one build log as per-node rows (`name`, `status`, `duration`, `path`).

### Comparing artifacts

- **`diff_nodes()`, `diff_artifacts()`, `diff_objects()`**: Compare runtime-native artifacts that have no direct T equivalent (R models and lists via diffobj, Python objects via unified diff, Julia objects via DeepDiffs).

### Shared arguments

- **`which_log`**: Regular expression selecting a specific build log filename. Defaults to the latest build.
- **`pipeline_dir`**: Pipeline directory. Defaults to `"_pipeline"`.
- **`return_path`**: Return the artifact path instead of deserializing it.
- **`include` / `direction`**: For tree and lineage reads, one of `"children"`, `"parents"`, or `"both"` (default `"children"` for trees, `"both"` for lineage).
- **`on_unreadable`**: For tree reads, one of `"error"` (default), `"path"`, or `"skip"`. With `"path"`, an unreadable node maps to a path/serializer record. Both fallbacks warn naming the node, the serializer, the artifact path, and the error.
- **`verify`**: For `show_code()`, check a script file against its recorded content hash. Raises on drift, on a missing file, and when no hash was recorded.

### Automatic readers by serializer

| Serializer | R reader (package) | Python reader (package) | Julia reader (package) |
|---|---|---|---|
| `default` | `readRDS()` (base) | `pickle`, then `dill`, then `cloudpickle` (stdlib) | `Serialization.deserialize` (stdlib) |
| `^json` | `jsonlite::read_json()` (`jsonlite`) | `json.load()` (stdlib) | `JSON.parsefile()` (`JSON`) |
| `^csv` | `read.csv()` (base) | `pandas.read_csv()` (`pandas`) | `CSV.read()` (`CSV`, `DataFrames`) |
| `^ipc` | `arrow::read_ipc_file()` (`arrow`) | `pyarrow.ipc` (`pandas`, `pyarrow`) | `Arrow.Table` (`Arrow`, `DataFrames`) |
| `^parquet` | `arrow::read_parquet()` (`arrow`) | `pyarrow.parquet` (`pandas`, `pyarrow`) | `Parquet2.readfile()` (`Parquet2`, `DataFrames`) |
| `^text` | exact file bytes (base) | exact file bytes (stdlib) | exact file bytes (stdlib) |
| `^pmml`, `^onnx`, `^bin` | no built-in reader | no built-in reader | no built-in reader |

Missing reader packages raise an error naming the package and the `tproject.toml` entries. `^pmml`, `^onnx`, and `^bin` always raise: use `return_path = TRUE` plus a custom deserializer.

### Cross-language notes

- `^json` simplifies vectors in R (`simplifyVector = TRUE`), so arrays of records can come back as data frames, while Python and Julia return plain dicts and lists.
- `^text` returns exact file bytes in all three languages.
- Lineage order is sorted within each level in every language, so trees compare equal across R, Python, and Julia.
- `inspect_pipeline()` and the frame helpers return a data frame in R and a list of dicts in Python and Julia.

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

# Read a node plus its downstream nodes
tree <- read_node_tree("clean_data")

# Read a failed node's error and warnings (same names as T)
msg <- error_msg("model")
msg <- warning_msg("model")

# Show a node's source for copy-paste tweaking
cat(show_code("model"))
```

```r
# Compare R-native artifacts across historical builds
diff <- diff_nodes("model", "model", which_log_a = "20260501", which_log_b = "latest")
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

# Read a node plus its downstream nodes
tree = tlang.read_node_tree("clean_data")

# Read a failed node's error and warnings (same names as T)
msg = tlang.error_msg("model")
msg = tlang.warning_msg("model")

# Show a node's source for copy-paste tweaking
print(tlang.show_code("model"))
```

```python
# Compare Python-native artifacts across historical builds
diff = tlang.diff_nodes("model", "model", which_log_a="20260501", which_log_b="latest")
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

# Read a node plus its downstream nodes
tree = read_node_tree("clean_data")

# Read a failed node's error and warnings (same names as T)
msg = error_msg("model")
msg = warning_msg("model")

# Show a node's source for copy-paste tweaking
println(show_code("model"))
```

---

## How it Works

When you run `build_pipeline()`, T-Lang generates a timestamped build log (e.g., `_pipeline/build_log_20260514_160236.json`). These helper packages:

1.  Scan the `_pipeline/` directory for `build_log_*.json` files.
2.  Sort them reverse-alphabetically to find the most recent one.
3.  Parse the JSON to find the entry for the requested node.
4.  Resolve the `path` (which might be relative to the project root or an absolute Nix store path).
5.  Pick the reader from the entry's `serializer` field (see the table above), or call the custom `deserializer` when one is passed.

When T's `node_diff()` delegates to these helpers for runtime-native object
comparisons, it preserves the original native artifact only for nodes using the
standard `default` or `tobj` serializers. If you use a custom serializer name,
call the helper package directly and pass the matching deserializer yourself.
Julia-native diffs invoked from T currently launch a fresh Julia helper process
for each comparison, so repeated large diffs will include Julia startup cost.
