# T Project Development Guide

This guide walks you through creating and developing a **T project** — a data analysis project that uses T packages.

> **Package vs Project**: A *package* is a reusable library of T functions. A *project* is a data analysis workspace that depends on packages.

## 1. Creating a Project

Create a new project interactively:

```bash
$ t init --project housing-analysis
Initializing new T project...
Author [User]: Alice
License [EUPL-1.2]: EUPL-1.2
Nixpkgs date [2026-02-19]: 2026-02-19

✓ Project 'housing-analysis' created successfully!
```

### 1.1 AI Agent Onboarding (Optional)

When running `t init`, you will be prompted to select an **AI Agent Context Level**. This generates two essential files in your project root:

- **AGENTS.md**: A project-specific guide for AI assistants (and human collaborators).
- **T-LANGUAGE-REFERENCE.md**: A technical reference of the T language tailored to the requested depth (small, medium, full, or huge).

These files are designed to be read by LLMs (like Antigravity, Claude, or ChatGPT) at the start of a session to give them immediate, high-fidelity context about your project and the specific version of T you are using.

This creates the following structure:

- **tproject.toml**: Project metadata and dependencies.
- **flake.nix**: Reproducible environment definition.
- **README.md**: Project documentation.
- **.gitignore**: Git exclusion list.
- **src/**: Your analysis scripts (e.g., `pipeline.t`).
- **data/**: Data files.
- **outputs/**: Output directory for results.
- **tests/**: Project-specific tests.
- **AGENTS.md**: Onboarding guide for AI Agents.
- **T-LANGUAGE-REFERENCE.md**: Tiered language reference for LLMs.
- **.claude/skills/SKILL.md**: An AI agent skill file that teaches LLMs how to work with T projects (scaffolded automatically).

## 2. Entering the Development Environment

Projects use Nix for reproducibility. Enter the development shell:

```bash
$ nix develop
```

This ensures all dependencies (T, packages, R, Nix) are available at the exact versions specified in `flake.lock`.

## 3. Adding Dependencies

Dependencies on T packages are declared in `tproject.toml`:

```toml
[project]
name = "housing-analysis"
description = "Analyzing housing data with T"

[dependencies]
my_stats = { git = "https://github.com/user/my-stats", tag = "v0.1.0" }
data_utils = { git = "https://github.com/user/data-utils", tag = "v0.2.0" }

[t]
min_version = "0.54.2"
```

### 3.1 System Dependencies and LaTeX

Beyond T packages, you can declare system-level tools and LaTeX packages required for your project.

#### Additional Tools

Use the `[additional-tools]` section to add any package from Nixpkgs (e.g., CLI utilities, compilers, or libraries):

```toml
[additional-tools]
# These will be available in your 'nix develop' shell and pipeline sandboxes
packages = ["git", "jq", "gawk", "pandoc"]
```

#### LaTeX Support

If your project involves generating PDFs or reports, use the `[latex]` section. T automatically provides a `texlive` environment starting from `scheme-small`. Just list any additional LaTeX packages you need:

```toml
[latex]
# Standard LaTeX packages
packages = ["amsmath", "blindtext", "physics", "hyperref"]
```

After adding or changing dependencies (including `[additional-tools]` or `[latex]` sections), run:

```bash
$ t update
Syncing 2 dependency(ies) from tproject.toml → flake.nix...
Running nix flake update...
```

This regenerates `flake.nix` so new dependencies and tools appear as proper flake inputs with locked versions. The tools will be available directly in your shell and automatically provided to any pipeline nodes during execution. When you declare runtime dependencies, the matching `tlang` companion package is also exposed in the project shell (`library(tlang)` for R, `import tlang` for Python, and `using tlang` for Julia). Then re-enter the shell:

```bash
$ nix develop
```

### 3.2 Upgrading T and Nixpkgs

To upgrade your project to the latest version of T and set the project's nixpkgs date to today's UTC date:

```bash
$ t upgrade
Checking for new T releases...
Upgrading project to T 0.53.0 and nixpkgs date 2026-05-08 (today's UTC date)...
Regenerating flake.nix and updating dependencies...
Running nix flake update...
```

This updates your `tproject.toml` and then runs `t update` automatically.

### 3.3 R Dependencies

R packages can be managed via the default nixpkgs resolver or by pointing T at an `renv.lock` file.

#### 3.3.1 Nixpkgs Resolver (default)

List CRAN packages from nixpkgs directly:

```toml
[r-dependencies]
packages = ["dplyr", "ggplot2", "jsonlite"]
```

After editing, run `t update` to include them in `flake.nix`. Packages are available in every R pipeline node and in `nix develop`.

#### 3.3.2 renv Resolver

If your project already has an `renv.lock` file, set:

```toml
[r-dependencies]
resolver = "renv"
```

When `resolver = "renv"`, T automatically discovers all R dependencies from `renv.lock`:

- **CRAN packages** are read from each entry's `Repository` or `Bioconductor` field and mapped to `pkgs.rPackages.*`.
- **GitHub/GitLab packages** are fetched via `builtins.fetchGit` using the `RemoteHost`, `RemoteUsername`, `RemoteRepo`, and `RemoteSha` fields.
- The **`Remotes` field** is parsed: entries like `user/repo` are matched against packages in the lock file and injected as `buildInputs` of the declaring git package.
- Supported remote hosts: `api.github.com` and `gitlab.com`. Other sources (bitbucket, custom URLs) produce a warning and are skipped.
- Base R packages (`R`, `methods`, `stats`, etc.) are automatically filtered out.

No `packages` list is required — `renv.lock` is the single source of truth. Run `t update` to regenerate `flake.nix` with the renv-discovered packages.

#### 3.3.3 Git R Packages

Declare R packages from remote Git repositories directly in `tproject.toml`:

```toml
[r-dependencies]
packages = ["dplyr"]
my_pkg = { git = "https://github.com/user/my-pkg", rev = "abc123def456" }
```

The `rev` field must be a full Git commit hash. Each git package is injected into every R pipeline node's `buildInputs`.

When using `resolver = "renv"`, git packages from `renv.lock` are automatically merged with those declared in `tproject.toml`.

### 3.4 Python Dependencies

Python packages can use the default nixpkgs resolver or the UV workspace resolver for PyPI-only dependencies.

#### 3.4.1 Nixpkgs Resolver (default)

List packages from the pinned nixpkgs revision:

```toml
[py-dependencies]
packages = ["pandas", "scikit-learn"]
```

Run `t update` to generate a `python.withPackages` environment in `flake.nix`. Simple, no extra files needed.

#### 3.4.2 UV Workspace Resolver

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

When `resolver = "uv"`, do not set `[py-dependencies].packages`; Python dependencies are declared only in `pyproject.toml` and locked by `uv.lock`. Running `t update` generates uv2nix/pyproject.nix inputs in `flake.nix` and builds the Python environment as a Nix virtual environment.

#### 3.4.3 Setting up a UV workspace from scratch

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

Add any PyPI packages to the `dependencies` list. Re-run `uv lock` whenever the list changes.

**4. Generate the lock file**

You need `uv` and `python3` on `PATH`. If you do not have them installed, enter a temporary Nix shell:

```bash
nix shell nixpkgs#uv nixpkgs#python3
```

Then generate the lock file:

```bash
uv lock --project python
```

Type `exit` or press `Ctrl-D` to leave the Nix shell when done, or keep it open for the next step.

**5. Generate the Nix flake**

```bash
t update
```

This reads the UV workspace, adds `pyproject-nix`, `uv2nix`, and `pyproject-build-systems` inputs to `flake.nix`, and configures the Python environment to use `pySet.mkVirtualEnv` instead of `pkgs.python314.withPackages`.

**6. Run your pipeline**

```bash
nix develop
t run src/pipeline.t
```

Python pipeline nodes work identically regardless of which resolver you chose.

**Adding or removing dependencies later**

1. Edit `dependencies` in `python/pyproject.toml`.
2. Re-run `uv lock --project python`.
3. Re-run `t update` to regenerate `flake.nix`.
4. Commit the updated `pyproject.toml` and `uv.lock`.

## 4. Importing Packages

Once inside `nix develop`, you can use the `import` statement in your T scripts to load package functions.

### Import All Public Functions

```t
import my_stats
```

This makes all public functions from `my_stats` available in scope.

### Import Specific Functions

```t
import my_stats[weighted_mean, correlation]
```

Only `weighted_mean` and `correlation` are imported.

### Import with Aliases

```t
import my_stats[wmean=weighted_mean, cor=correlation]
```

`weighted_mean` is available as `wmean`, `correlation` as `cor`.

### Visibility

All functions in a package are **public by default**. Package authors can mark internal helpers as private using `@private` in T-Doc comments — those functions will not be visible to importers.

## 5. Writing Analysis Scripts

Write your analysis in `src/`. For example, `src/pipeline.t`:

```t
import my_stats
import data_utils[read_clean]

p = pipeline {
  data = read_csv("data/housing.csv")
  clean = read_clean(data)
  avg_price = mean(clean.$price)
  price_by_area = clean |>
    group_by($area) |>
    summarize(avg=mean($price), sd=sd($price))
}

build_pipeline(p)
print(price_by_area)
```

Run your script:

```bash
$ t run src/pipeline.t
```

Or use the REPL for interactive exploration:

```bash
$ t repl
```

## 6. Running Tests

You can add tests in `tests/` following the same conventions as packages:

```t
-- tests/test-pipeline.t
import my_stats

result = weighted_mean([1, 2, 3], [0.5, 0.3, 0.2])
assert(result == 1.7)
```

Run them with:

```bash
$ t test
```

### Skipping Pipeline Tests Conditionally

Since pipeline nodes are compiled and executed via Nix, tests that build or run pipelines might fail or block in sandboxed environments or systems lacking Nix. You can conditionally skip the execution of specific pipeline nodes using the `noop` parameter with any T expression.

Because `noop` accepts T expressions (evaluated at runtime), you can pass conditions referencing environment variables:

```t
import my_project

p = pipeline {
  heavy_node = node(
    command = <{ run_heavy_nix_job() }>,
    # Skip execution if not running in CI
    noop = (env_var("CI") == "")
  )
}

res = build_pipeline(p)

# Because errors are first-class values in T, skipped nodes propagate VError values cleanly.
# You can check if the node was skipped using expect_error or custom checks:
assert(expect_error(read_node(res.heavy_node), class = "TypeError", message = "was skipped"))
```

## 7. Reproducibility

Your project is fully reproducible through Nix:

- **`flake.nix`** declares exact dependency sources (managed by `t update`)
- **`flake.lock`** pins exact versions of all inputs
- **`tproject.toml`** is the human-readable source of truth for dependencies

Anyone can reproduce your environment:

```bash
$ git clone https://github.com/user/housing-analysis
$ cd housing-analysis
$ nix develop
$ t run src/pipeline.t
```

The same T version, same package versions, same R packages, and same system libraries are used every time.

## 8. IDE Support & Autocompletion

T projects are designed to work seamlessly with modern editors via the **Language Server Protocol (LSP)**.

### Using the LSP

The `t-lsp` binary is provided automatically by your project's `nix develop` shell. 

1.  Configure your editor (Vim, Emacs, or VS Code) once following the [Editor Support Guide](editors.md).
2.  Launch your editor *inside* the project directory after running `nix develop`.
3.  Alternatively, use **direnv** to automatically load the environment when you enter the project folder.

### Using the Atelier TUI IDE

T projects also support [Atelier](https://github.com/b-rodrigues/atelier), a
tmux-based TUI IDE that provides a split-pane environment with an embedded
editor, REPL, file tree, variable watcher, pipeline diagram, and plot viewer.
To enable Atelier in a new project, pass `--include-atelier` to `t init`. Once
inside `nix develop`, simply run `atelier`.

Once active, you will get real-time autocompletion for:
-   **Package functions**: Suggestions for all imported functions.
-   **Local variables**: Defined earlier in your script.
-   **DataFrame columns**: Column names from your data sources (accessible via the `$` prefix).

---

## Next Steps

1. **[Language Overview](language_overview.md)** — Learn about types, syntax, and logic.
2. **[Pipeline Tutorial](pipeline_tutorial.md)** — Learn how to structure your analysis as a DAG.
3. **[API Reference](api-reference.md)** — Explore the standard library.
4. **[Data Manipulation Examples](data_manipulation_examples.md)** — More worked examples of data wrangling.
