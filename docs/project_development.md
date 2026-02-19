# T Project Development Guide

This guide walks you through creating and developing a **T project** — a data analysis project that uses T packages.

> **Package vs Project**: A *package* is a reusable library of T functions. A *project* is a data analysis workspace that depends on packages.

## 1. Creating a Project

Create a new project interactively:

```bash
$ t init project
Initializing new T package/project...
Name [my_project]: housing-analysis
Author [User]: Alice
License [EUPL-1.2]: EUPL-1.2
Nixpkgs date [2026-02-19]: 2026-02-19

✓ Project 'housing-analysis' created successfully!
```

This creates the following structure:

- **tproject.toml**: Project metadata and dependencies.
- **flake.nix**: Reproducible environment definition (managed automatically).
- **src/**: Your analysis scripts (e.g., `analysis.t`).
- **data/**: Data files.
- **README.md**: Project documentation.

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
min_version = "0.5.0"
```

After adding or changing dependencies, run:

```bash
$ t update
Syncing 2 dependency(ies) from tproject.toml → flake.nix...
Running nix flake update...
```

This regenerates `flake.nix` so new dependencies appear as proper flake inputs with locked versions. Then re-enter the shell:

```bash
$ nix develop
```

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

Write your analysis in `src/`. For example, `src/analysis.t`:

```t
import my_stats
import data_utils[read_clean]

-- Load and clean data
data = read_csv("data/housing.csv")
clean = read_clean(data)

-- Analyze
avg_price = mean(clean.$price)
price_by_area = clean |>
  group_by($area) |>
  summarize(avg=mean($price), sd=sd($price))

print(price_by_area)
```

Run your script:

```bash
$ t run src/analysis.t
```

Or use the REPL for interactive exploration:

```bash
$ t repl
```

## 6. Running Tests

You can add tests in `tests/` following the same conventions as packages:

```t
-- tests/test-analysis.t
import my_stats

result = weighted_mean([1, 2, 3], [0.5, 0.3, 0.2])
assert(result == 1.7)
```

Run them with:

```bash
$ t test
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
$ t run src/analysis.t
```

The same T version, same package versions, same R packages, and same system libraries are used every time.
