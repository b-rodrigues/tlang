# T — A Reproducibility-First Language for Tabular Data

T is an experimental programming language for declarative, functional manipulation of tabular data. Inspired by R's tidyverse and OCaml's type discipline, T aims to make data manipulation clear, expressive, and **fully reproducible**. This project is in a **very early, exploratory phase** and is being developed entirely through AI-assisted generation.


## Reproducibility as a Core Principle

T is designed around **reproducibility first**. Every aspect of the language, tooling, and ecosystem prioritizes perfect reproducibility:

1. **Nix for Package Management**: T uses Nix as its package manager—not just for T packages, but for entire projects. Nix ensures that the same code produces identical results across all environments and time periods.

2. **Intent Blocks for LLM Collaboration**: T provides structured `intent` blocks that capture assumptions, constraints, and goals in a machine-readable format, making LLM-assisted development reproducible and auditable.

3. **Explicit Semantics**: No hidden behavior, no implicit coercion, no silent failures. Every operation is explicit, making code predictable and reproducible by default.

---

## Project Status

This project is at **alpha stage** (v0.1). The core language syntax and semantics are frozen for the alpha release. All eight implementation phases are complete, covering the language core, tabular data, pipelines, data manipulation, math/statistics, LLM tooling hooks, CLI/REPL, and stabilization.

For detailed release notes, see [ALPHA.md](ALPHA.md). For future plans, see [ROADMAP.md](ROADMAP.md).

---

## Design Goals

- **Data analysis as a pipeline**: While it'll be possible to write simple scripts, idiomatic T code will be written as a reproducible analytical pipeline.
- **DataFrame-first**: DataFrames are first-class values. Functions like `select()`, `filter()`, and `mutate()` operate on them declaratively.
- **1-indexed**: Humans don't start counting from 0, only clankers do. You aren't a clanker aren't you?
- **Declarative and functional**: T is expression-oriented and avoids mutation and imperative constructs.
- **Minimal OCaml core**: The runtime and interpreter are minimal. Most functionality is implemented as packages written in T itself.
- **Non-Standard Evaluation (NSE)**: Column names can be passed as bare identifiers, not strings: `select(name, age)`.
- **Extensible built-ins**: Functions like `print()` support multiple dispatch and can be extended for user-defined types.
- **REPL-first**: T is designed to be explored interactively via a custom REPL.
- **Package-based**: Features are grouped into internal packages (e.g. `core`, `stats`, `colcraft`) that load modularly.
- **LLM-native**: Intent blocks enable structured, reproducible collaboration with AI assistants.
- **Nix-managed**: Perfect reproducibility through Nix package management.

---
## Why T?

T is not aiming to replace R or replicate its vast package ecosystem. R remains one of the most powerful tools for data analysis, with decades of community contributions. Instead, T is for those who prefer a **small, focused, consistent language** dedicated to data wrangling, graphics, and basic statistics — without general-purpose baggage.

T's value lies in its philosophy: **data analysis should be treated as a reproducible pipeline**. While you can write simple scripts, idiomatic T code encourages a structured, step-by-step process that is clear, verifiable, and robust, inspired by the R package `{targets}`.

### Perfect Reproducibility Through Nix

Unlike traditional package managers (npm, PyPI, CRAN), T uses **Nix as its package manager**. This is a fundamental design choice that provides:

- **Zero dependency conflicts**: Nix makes dependency hell impossible
- **Time-independent builds**: The same project works identically years later
- **Environment isolation**: No interference from system packages
- **Guaranteed reproducibility**: Same inputs always produce identical outputs

Every T project is a Nix flake that pins exact versions of all dependencies, including T itself, packages, and system libraries. This means your analysis will produce the same results today, tomorrow, and five years from now.

### LLM-Native Collaboration

T embraces AI-assisted development as a first-class workflow through **intent blocks**:

```t
intent {
  description: "Analyze customer churn patterns",
  assumes: "Data excludes test accounts",
  requires: "churn_rate should be between 0 and 1"
}
```

Intent blocks provide:
- **Structured context** for LLM code generation
- **Machine-readable assumptions** and constraints
- **Auditable collaboration** between humans and AI
- **Reproducible workflows** where intent is explicit, not implicit

This makes T ideal for teams using LLMs to accelerate data analysis while maintaining code quality and reproducibility.

### Core Values

T's value lies in being:

- **Minimal**: a language you can learn and understand fully
- **Self-contained**: every function and abstraction is inspectable and documented
- **Purpose-built**: designed *only* for working with structured data
- **Reproducible**: Nix-managed environment guarantees perfect reproducibility
- **LLM-friendly**: structured intent blocks enable reliable AI collaboration

It's ideal for users who want a compact environment, excellent documentation, and a predictable, REPL-first workflow — whether for teaching, scripting, or exploratory data work.
---

## Example

```t
-- Intent block for LLM collaboration
intent {
  description: "Analyze customer age and income patterns",
  assumes: "Data is pre-cleaned and age > 0",
  requires: "Model R-squared should be reported"
}

-- Load and transform data
data = read_csv("data.csv")
data |> select("name", "age") |> filter(\(row) row.age > 30)

-- Save results with write_csv
data |> filter(\(row) row.age > 30) |> \(d) write_csv(d, "filtered.csv")

-- Linear regression with formula syntax
model = lm(data = data, formula = age ~ income)
print(model.slope)
print(model.r_squared)

-- Error recovery with maybe-pipe
safe_result = error("missing") ?|> \(x) if (is_error(x)) "default" else x
```

Features supported:

- **Intent blocks**: `intent { ... }` for structured LLM collaboration
- R-style lambdas: `\(x) x + 1`
- Formula syntax: `y ~ x` creates Formula objects for statistical modeling
- Named arguments: `lm(data = df, formula = y ~ x)`
- NA handling: `mean(data, na_rm = true)` skips missing values
- CSV I/O: `read_csv(path, sep = ";", skip_lines = 2)` and `write_csv(df, path, sep = ";")`
- Window functions: `row_number`, `min_rank`, `dense_rank`, `lag`, `lead`, `cumsum` with NA support
- Conditional pipe: `x |> f` (short-circuits on error)
- Maybe-pipe: `x ?|> f` (forwards errors for recovery)
- Python-style list comprehensions: `[x * x for x in numbers if x > 2]`
- Python-style dictionaries: `{name: "Alice", age: 30}`

---
## Standard Packages

The following packages are automatically loaded at REPL startup:

- `core`: functional utilities (e.g. `map`, `filter`)
- `stats`: statistical functions (e.g. `mean`, `sd`)
- `colcraft`: tabular functions (`select`, `mutate`, `filter`, `arrange`, `group_by`, `summarize`) and window functions (`row_number`, `min_rank`, `dense_rank`, `lag`, `lead`, `cumsum`, etc.)

Each package consists of one file per function, e.g. `colcraft.select.ml`.

---

## Reproducible Package Management with Nix

T does not use a decentralized package registry like PyPI or npm. Instead, **Nix is T's package manager**, ensuring perfect reproducibility.

### Why Nix?

Traditional package managers suffer from:
- **Dependency hell**: Conflicting version requirements
- **Time drift**: Packages updated, breaking old code
- **Environment contamination**: Global packages interfering with projects

Nix solves all of these by:
- **Isolating environments**: Each project has its own dependencies
- **Pinning versions**: Exact package versions locked forever
- **Guaranteeing reproducibility**: Same code, same results, always

### Package Distribution

All T packages are contributed and maintained as **individual git repositories** with releases:

- Authors publish packages to GitHub/GitLab with tagged releases
- Projects reference packages by git URL and version tag
- Nix ensures all dependencies are fetched and built consistently
- Date-pinned nixpkgs snapshot ensures R packages remain stable

This provides the flexibility of decentralized publishing with the reliability of centralized curation, without the fragility common in traditional package ecosystems.

For details on creating packages and projects, see [package-management.md](package-management.md).

---
## Project Structure

```
.
├── flake.nix            # Nix flake-based build
├── ast.ml               # Abstract syntax tree
├── parser.ml            # Recursive descent parser
├── lexer.ml             # Tokenizer
├── eval.ml              # Interpreter / evaluator
├── repl.ml              # Read-eval-print loop
├── csv_reader.ml        # CSV integration
├── packages/
│   ├── core/
│   │   └── map.t
│   ├── stats/
│   │   └── mean.t
│   └── colcraft/
│       └── select.t
```

---

## Building

### Quick Start with Nix

The easiest way to try T is with Nix:

```bash
# Try T directly from GitHub (no installation needed!)
nix run github:b-rodrigues/tlang

# Run a hello world example
nix run github:b-rodrigues/tlang -- run examples/hello.t

# Run a one-liner
echo 'print("Hello, T!")' | nix run github:b-rodrigues/tlang -- run /dev/stdin
```

## Installation

### Building from Source

```bash
# Clone the repository
git clone https://github.com/b-rodrigues/tlang.git
cd tlang

# Enter the Nix development environment
nix develop

# Build the project
dune build

# Run the REPL
dune exec src/repl.exe
```

For detailed usage instructions, see [USAGE.md](USAGE.md).

## Documentation

- [Language Overview](docs/language_overview.md) — Complete language reference
- [Formulas](docs/formulas.md) — Formula syntax and `lm()` reference
- [Pipeline Tutorial](docs/pipeline_tutorial.md) — Step-by-step pipeline guide
- [Data Manipulation Examples](docs/data_manipulation_examples.md) — Practical data wrangling cookbook
- [Alpha Release Notes](ALPHA.md) — What's included in the alpha
- [Roadmap](ROADMAP.md) — Future plans beyond alpha
- [Changelog](CHANGELOG.md) — Version history

## Development

To hack on T:

```bash
# Clone the repo
git clone https://github.com/b-rodrigues/tlang.git
cd tlang

# Enter the development environment
nix develop

# You now have access to:
# - OCaml compiler and tools
# - Dune build system
# - Language server (ocaml-lsp)
# - Code formatter (ocamlformat)
# - Interactive REPL (utop)

# Build and test
dune build
dune test

# Run the T REPL
dune exec src/repl.exe
```

---


## Testing

T uses a comprehensive golden testing framework that compares outputs against
R's dplyr and stats packages.

### Run All Tests

```bash
make test         # OCaml unit tests
make golden       # Golden tests (T vs R)
```

### Test Coverage

See [Golden Testing Documentation](tests/golden/README.md) for details.

---


## Contributing

There is no external package registry. All contributions are made directly to the GitHub repo. You can add new T packages under `packages/<name>/`, and define functions as `.t` files or integrate OCaml-backed functions in `src`.

---

## License

EUPL v1.2.
