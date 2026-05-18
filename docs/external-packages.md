# External Helper Packages (R, Python, Julia)

To facilitate the consumption of T-Lang build artifacts from within other languages, we provide lightweight helper packages for **R**, **Python**, and **Julia**. All these packages are named **`tlang`** in their respective ecosystems. These packages allow you to easily locate and read built nodes from a T pipeline without manually parsing build logs or resolving Nix store paths.

## Automatic Availability

These packages are **automatically installed and loaded** in every R, Python, and Julia node in a T pipeline. You do not need to install them manually. The `read_node()` function and its dependencies are ready to use immediately.

For project development shells, `t update` also wires the matching companion package into `flake.nix` whenever you declare dependencies in `[r-dependencies]`, `[py-dependencies]`, or `[jl-dependencies]`, so the helper is available from `nix develop` as well.

## Key Features

- **`read_node(name)`**: Automatically locates the latest build log in the `_pipeline/` directory, finds the requested node, and deserializes its artifact.
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

# Inspect the pipeline DAG (returns a Dict)
nodes = pipeline_nodes()
```

---

## How it Works

When you run `build_pipeline()`, T-Lang generates a timestamped build log (e.g., `_pipeline/build_log_20260514_160236.json`). These helper packages:

1.  Scan the `_pipeline/` directory for `build_log_*.json` files.
2.  Sort them reverse-alphabetically to find the most recent one.
3.  Parse the JSON to find the entry for the requested node.
4.  Resolve the `path` (which might be relative to the project root or an absolute Nix store path).
5.  Call the appropriate deserializer (`readRDS` for R, `pickle.load` for Python, `Serialization.deserialize` for Julia).
