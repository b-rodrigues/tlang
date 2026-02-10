# T — A Functional Language for Tabular Data

T is an experimental programming language for declarative, functional manipulation of tabular data. Inspired by R’s tidyverse and OCaml’s type discipline, T aims to make data manipulation clear, expressive, and extensible. This project is in a **very early, exploratory phase** and is being developed entirely through AI-assisted generation.

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

---

## Why T?

T is not aiming to replace R or replicate its vast package ecosystem. R remains one of the most powerful tools for data analysis, with decades of community contributions. Instead, T is for those who prefer a **small, focused, consistent language** dedicated to data wrangling, graphics, and basic statistics — without general-purpose baggage.

T’s value lies in its philosophy: **data analysis should be treated as a reproducible pipeline**. While you can write simple scripts, idiomatic T code encourages a structured, step-by-step process that is clear, verifiable, and robust, inspired by the R package `{targets}`.

T’s value lies in being:

- **Minimal**: a language you can learn and understand fully
- **Self-contained**: every function and abstraction is inspectable and documented
- **Purpose-built**: designed *only* for working with structured data

It's ideal for users who want a compact environment, excellent documentation, and a predictable, REPL-first workflow — whether for teaching, scripting, or exploratory data work.
 
---

## Example

```t
-- Load and transform data
data = read_csv("data.csv")
data |> select("name", "age") |> filter(\(row) row.age > 30)

-- Linear regression with formula syntax
model = lm(data = data, formula = age ~ income)
print(model.slope)
print(model.r_squared)

-- Error recovery with maybe-pipe
safe_result = error("missing") ?|> \(x) if (is_error(x)) "default" else x
```

Features supported:

- R-style lambdas: `\(x) x + 1`
- Formula syntax: `y ~ x` creates Formula objects for statistical modeling
- Named arguments: `lm(data = df, formula = y ~ x)`
- Conditional pipe: `x |> f` (short-circuits on error)
- Maybe-pipe: `x ?|> f` (forwards errors for recovery)
- Python-style list comprehensions: `[x * x for x in numbers if x > 2]`
- Python-style dictionaries: `{name: "Alice", age: 30}`

---

## Standard Packages

The following packages are automatically loaded at REPL startup:

- `core`: functional utilities (e.g. `map`, `filter`)
- `stats`: statistical functions (e.g. `mean`, `sd`)
- `colcraft`: tabular functions (`select`, `mutate`, `filter`, etc.)

Each package consists of one file per function, e.g. `colcraft.select.ml`.

---

## Package Philosophy

T does not use a decentralized package registry like PyPI or npm. Instead, all packages are contributed and maintained **within the main GitHub repository**. This is a deliberate design decision inspired by R’s CRAN, but with key differences.

While CRAN prevents dependency hell by enforcing a single coherent view of all packages, its contribution process can lack transparency and flexibility. By keeping all T packages in a single, centralized repository on GitHub, we gain:

- A consistent, minimal dependency graph across the ecosystem
- Full visibility into how packages are reviewed and integrated
- Simple and direct contributions via GitHub PRs

This ensures long-term maintainability without the fragility and version drift issues common in Python packaging, while remaining open and collaborative.

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
