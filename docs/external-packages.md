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

# Compare Julia-native artifacts across historical builds
diff = diff_nodes("my_model", "my_model", which_log_a="20260501", which_log_b="latest")

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

When T's `node_diff()` delegates to these helpers for runtime-native object
comparisons, it preserves the original native artifact only for nodes using the
standard `default` or `tobj` serializers. If you use a custom serializer name,
call the helper package directly and pass the matching deserializer yourself.
Julia-native diffs invoked from T currently launch a fresh Julia helper process
for each comparison, so repeated large diffs will include Julia startup cost.

## Optional UV/uv2nix Python environments

T's default Python dependency resolver remains nixpkgs: list packages in `[py-dependencies].packages`, run `t update`, and the generated flake uses `python.withPackages` from the pinned nixpkgs revision.

### Choosing a Resolver: Nixpkgs vs. UV

To decide which Python dependency resolver is best for your project:

```text
                            Do you need PyPI-only packages,
                            highly specific versions, or a
                            complex Python project stack?
                                     /         \
                                   No           Yes
                                  /               \
            Use Default Nixpkgs Resolver      Use UV Workspace Resolver
            - Simple config in tproject.toml   - Standard pyproject.toml + uv.lock
            - Quickest setup for casual users  - Best for Python-heavy codebases
```

*   **Use the Default (Nixpkgs) Resolver if:**
    *   You are primarily an R, Julia, or T developer who just needs a few standard Python packages (e.g., `pandas`, `scikit-learn`, `numpy`).
    *   You want the simplest possible configuration without managing extra files like `pyproject.toml` or `uv.lock`.
*   **Use the UV Workspace Resolver if:**
    *   You need PyPI-specific packages that are missing or outdated in `nixpkgs`.
    *   You require highly specific package versions or need to resolve complex dependencies.
    *   Your pipeline includes an extensive Python stack where lockfile-level reproducibility (via `uv.lock`) is desired.

Projects that need packages from PyPI can opt into UV explicitly:

```toml
[py-dependencies]
resolver = "uv"
workspace = "python"
```

The `version` field is **optional** when using the UV resolver. If omitted, T infers the Nixpkgs Python attribute (e.g. `python312`) from the `requires-python` field in `python/pyproject.toml`. The inference accepts specifiers that constrain to a single minor version (`==3.12`, `==3.12.*`, `~=3.12`, `>=3.12,<3.13`) and errors on open-ended ranges (`>=3.12`). If an explicit `version` conflicts with `requires-python`, T prints a warning and uses the explicit value.

The workspace directory must contain the UV project metadata and lock file:

```text
python/
  pyproject.toml
  uv.lock
```

When `resolver = "uv"`, do not set `[py-dependencies].packages`; Python dependencies are declared only in `pyproject.toml` and locked by `uv.lock`. Running `t update` generates uv2nix/pyproject.nix inputs in `flake.nix` and builds the Python environment as a Nix virtual environment. This keeps the Python node executor unchanged while avoiding mixed dependency resolution.

### Setting up a UV workspace from scratch

This walkthrough assumes you do **not** have `uv` installed and have **no** existing Python package metadata — you are starting from an empty T project.

**1. Create a new T project**

```bash
t project my_project
cd my_project
```

**2. Edit `tproject.toml`**

Replace the default `[py-dependencies]` section (or add it if missing):

```toml
[py-dependencies]
resolver = "uv"
workspace = "python"
```

The `version` field is optional when using the UV resolver — T infers it from `requires-python` in `pyproject.toml`. Remove any `packages` key if present — UV and `packages` are mutually exclusive.

**3. Create the Python workspace directory and `pyproject.toml`**

Create the workspace directory and a PEP 621 `pyproject.toml` that lists your dependencies:

```bash
mkdir python
```

```toml
# python/pyproject.toml
[project]
name = "my_project_python_env"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "pandas",
]
```

Add any PyPI packages you need to the `dependencies` list. If you are unsure what you need, start with one package and add more later — you can re-run `uv lock` whenever the list changes.

**4. Generate the lock file**

You need `uv` and `python3` on `PATH`. If you do not have them installed, enter a temporary Nix shell:

```bash
nix shell nixpkgs#uv nixpkgs#python3
```

Then generate the lock file:

```bash
uv lock --project python
```

This reads `python/pyproject.toml`, resolves the declared dependencies against PyPI, and writes `python/uv.lock`.

Type `exit` or press `Ctrl-D` to leave the Nix shell when done, or keep it open for the next step.

**5. Generate the Nix flake**

```bash
t update
```

This reads the UV workspace, adds `pyproject-nix`, `uv2nix`, and `pyproject-build-systems` inputs to `flake.nix`, and configures the Python environment derivation to use `pySet.mkVirtualEnv` instead of `pkgs.python314.withPackages`.

**6. Run your pipeline**

```bash
nix develop
t run src/pipeline.t
```

Python pipeline nodes work identically regardless of which resolver you chose — the change is transparent to your T code.

**Adding or removing dependencies later**

1. Edit `dependencies` in `python/pyproject.toml`.
2. Re-run `uv lock --project python` (from a shell with `uv` available).
3. Re-run `t update` to regenerate `flake.nix`.
4. Commit the updated `pyproject.toml` and `uv.lock`.
