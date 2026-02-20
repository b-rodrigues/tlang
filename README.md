# T Programming Language

**T** is an experimental, reproducibility-first programming language for declarative data manipulation and statistical analysis. Inspired by R's tidyverse and OCaml's type discipline, T is designed for teams and researchers who want a small, focused, understandable language dedicated to data wrangling, statistics, and analysis—without general-purpose programming baggage.

[![License: EUPL v1.2](https://img.shields.io/badge/License-EUPL%20v1.2-blue.svg)](LICENSE)
[![Status: Alpha](https://img.shields.io/badge/Status-Alpha%200.5-orange.svg)](https://tstats-project.org)

The goal is not to create a clone of R’s tidyverse, but to design a new, strictly functional 
programming language with deliberate constraints that make reproducibility a core design 
principle and provide guarantees other languages do not.

Rather than bolting on an integrated, imperative package manager, T is built from the 
ground up to be installed via Nix, and T packages are defined as Nix flakes. Any project 
that uses T therefore must use Nix from the outset, ensuring reproducibility by design and 
from day one.

Other constraints reinforce this philosophy: there are no loops and no mutable variables, 
significantly reducing the surface area for bugs. Another distinctive feature is the concept of 
“intent” blocks—structured, comment-like constructs embedded in code that can be easily parsed by 
LLMs. The aim is to make collaboration with LLMs as transparent and deterministic as possible.

T does not attempt to reinvent the wheel. It can be understood as a layer of syntactic and semantic 
sugar on top of Apache Arrow for data frames and tabular operations, Owl (the OCaml scientific 
computing library) for mathematics and statistics, and Nix for package management. Rather than 
replacing these foundations, T provides a coherent, opinionated interface over them.

R’s tidyverse is known for its strong user experience, and T deliberately adopts many of its design 
principles. As a result, it may feel like a clone at first glance: many tidyverse functions are 
intentionally reimplemented. However, this is a conscious UX choice, not an architectural one. Under 
the hood, T is grounded in a strictly functional core, reproducibility through Nix, and a different
execution and packaging model altogether.

Another deliberate “limitation” is that non-interactive scripts must be defined as pipelines. This 
constraint is intended to prevent the accumulation of ad hoc, spaghetti-style scripts in production 
contexts. The workflow model is explicit: exploratory work can be messy and iterative, but once 
stabilized, it should be transformed (potentially with the help of an LLM) into a well-structured, 
declarative pipeline.

I am still evaluating which pipeline engine to adopt. One possibility is to rely on Nix for this
layer as well, following the same approach I used for my R package *rixpress*. This would further 
consolidate reproducibility and execution semantics within a single, coherent system rather than 
introducing an additional orchestration framework.

Why “T”? The name is a nod to lineage and a bit of humor. R is a GPL-licensed 
reimplementation of S, and since T draws heavy inspiration from R, I thought calling it "T" would be
funny.

Why the EUPL? Because I love Europe and I love the GPL.

With all that said, this is a hobby project, 100% experimental, and made for fun. DO NOT USE IN PRODUCTION.

What is currently missing:

* **User-contributed packages**: This is currently a major focus of development. Infrastructure for creating, documenting, and distributing user packages is being implemented and will be available from the **Beta** release onwards.
* No graphics or plotting library.
* Only a subset of mathematical functions and dplyr-like verbs are implemented.
* Only linear regression is available for statistical modeling.
* No random number generators.
* Only CSV files can be read and written.

You guessed it, I welcome contributions!

## Quick Start

T is distributed via Nix, which is currently the only supported installation method.

Start by launching a temporary shell that provides the `t` executable:

```bash
nix shell github:b-rodrigues/tlang
```

This drops you into an ephemeral environment with `t` available on your `PATH`.  
You can now bootstrap a new project:

```bash
t init my_t_project
```

You will be prompted to enter basic project information.

When finished, leave the temporary shell:

```bash
exit
```

This creates a new directory (e.g. `my_t_project/`) containing the necessary project files.  
The most important file is:

```
tproject.toml
```

This file declares your project's dependencies. Dependencies must be explicitly listed here, as they are used by the project-specific flake to provide a fully reproducible environment.

You can now start working on your project by editing:

```
src/analysis.t
```

You are free to rename this file or add additional source files as needed.

```t
-- Load data
df = read_csv("data.csv", clean_colnames = true)

-- Data manipulation pipeline using NSE (dollar-prefix) syntax
result = df
  |> filter($age > 30)
  |> select($name, $age, $salary)
  |> arrange($age, "desc")
  
-- Statistics
mean(df.salary, na_rm = true)
model = lm(data = df, formula = salary ~ age)
```

## Key Features

- **🔒 Perfect Reproducibility**: Every project is a Nix flake with pinned dependencies
- **📊 DataFrame-First**: First-class tabular data with Arrow backend, NSE column references (`$name`)
- **🔄 Pipeline-Oriented**: DAG-based computation with automatic dependency resolution
- **🤖 LLM-Native**: Intent blocks for structured AI collaboration
- **⚡ Explicit Semantics**: No silent failures, no implicit NA propagation
- **🔧 Functional**: Immutable values, closures, higher-order functions
- **📈 Statistical**: Built-in functions for data analysis and modeling

## Installation

T requires [Nix](https://nixos.org/) with flakes enabled:

```bash
# Clone the repository
git clone https://github.com/b-rodrigues/tlang.git
cd tlang

# Enter development environment
nix develop

# You might see following prompts, accept them all

#do you want to allow configuration setting 'extra-substituters' to be set to 'https://rstats-on-#nix.cachix.org' (y/N)? y
#do you want to permanently mark this value as trusted (y/N)? y
#do you want to allow configuration setting 'extra-trusted-public-keys' to be set to 'rstats-on-#nix.cachix.org-1:vdii...' (y/N)? y
#do you want to permanently mark this value as trusted (y/N)? y

# Start the REPL
dune exec src/repl.exe
```

See [Installation Guide](docs/installation.md) for detailed setup instructions.

## Documentation

- **[Getting Started](docs/getting-started.md)** — First steps with T
- **[Language Overview](docs/language_overview.md)** — Types, syntax, and core concepts
- **[Type System](docs/type-system.md)** — REPL vs strict mode, typed lambdas, and current limitations
- **[API Reference](docs/api-reference.md)** — Complete function reference
- **[Data Manipulation](docs/data_manipulation_examples.md)** — Practical examples with data verbs
- **[Pipeline Tutorial](docs/pipeline_tutorial.md)** — Step-by-step guide to pipelines
- **[Architecture](docs/architecture.md)** — Language design and implementation
- **[Contributing](docs/contributing.md)** — How to contribute to T

[**Full Documentation**](https://tstats-project.org)

## Example: Data Analysis

```t
-- Intent block for LLM collaboration
intent {
  description: "Analyze customer churn by age group",
  assumes: "Data excludes test accounts",
  requires: "age > 0, churn_rate between 0 and 1"
}

-- Load and clean data
customers = read_csv("customers.csv", clean_colnames = true)

-- Analysis pipeline using NSE dollar-prefix syntax
analysis = pipeline {
  filtered = customers |> filter($age > 18)
  
  by_age = filtered
    |> mutate($age_group = if ($age < 30) "young" else "mature")
    |> group_by($age_group)
    |> summarize($churn_rate = mean($churned))
  
  model = lm(data = filtered, formula = churned ~ age)
}

-- Access results
print(analysis.by_age)
print(analysis.model.r_squared)
```

## Core Language Features

### Pipe Operators

```t
-- Conditional pipe (|>) short-circuits on errors
[1, 2, 3] |> map(\(x) x * x) |> sum  -- 14

-- Maybe-pipe (?|>) forwards errors for recovery
error("fail") ?|> \(x) if (is_error(x)) 0 else x  -- 0

-- Pipes work naturally with NSE data verbs
df |> filter($age > 30) |> select($name, $salary)
```

### Explicit NA Handling

```t
-- NA does not propagate automatically
mean([1, NA, 3])              -- Error: NA encountered
mean([1, NA, 3], na_rm = true) -- 2.0 (explicit handling)
```

### Type System (Alpha)

T now includes an early type-system layer focused on function signatures and mode-dependent validation:

- `--mode repl` keeps exploration flexible and does not enforce top-level annotations.
- `--mode strict` enforces typed top-level function signatures.
- `t run file.t` defaults to `strict` mode (unless `--mode repl` is explicitly passed).

Current typed lambda syntax:

```t
-- Untyped lambda (expression body)
add = \(x, y) x + y

-- Typed lambda (return type in parentheses)
add_int = \(x: Int, y: Int -> Int) (x + y)

-- Generic typed lambda (type variables must be declared)
id = \<T>(x: T -> T) x
```

See [docs/type-system.md](docs/type-system.md) for details on what is implemented today and what is still planned.

### Data Verbs

T uses dollar-prefix (`$column`) syntax for concise column references (NSE):

```t
df |> select($name, $age)                              -- Select columns
df |> filter($age > 25)                                -- Filter rows
df |> mutate($bonus = $salary * 0.1)                   -- Add columns (named-arg)
df |> arrange($age, "desc")                            -- Sort
df |> group_by($dept) |> summarize($n = nrow($dept))   -- Aggregate (named-arg)
```

The `$col = expr` syntax uses NSE expressions that are auto-transformed into lambdas.

### Window Functions

```t
row_number([10, 30, 20])  -- Vector[1, 3, 2]
lag([1, 2, 3, 4])         -- Vector[NA, 1, 2, 3]
cumsum([1, 2, 3])         -- Vector[1, 3, 6]
```

## Design Philosophy

T is built on three core principles:

1. **Reproducibility First**: Nix-managed dependencies ensure identical results across time and environments
2. **Explicit Over Implicit**: No silent failures, automatic coercion, or hidden behavior
3. **Human-LLM Collaboration**: Intent blocks and pipeline structure enable auditable AI-assisted development

Unlike general-purpose languages, T makes deliberate trade-offs to stay small, focused, and predictable for data analysis workflows.

## Status

**Alpha 0.1** — Syntax and semantics frozen. The language is functional and ready for exploratory use. The current focus is on building the infrastructure for a robust, user-contributed package ecosystem, which is expected to be stable by the **Beta** release. Production use requires further testing and performance optimization.

## Project Structure

```
tlang/
├── src/
│   ├── ast.ml          # Abstract syntax tree
│   ├── lexer.mll       # Lexer specification
│   ├── parser.mly      # Parser grammar (Menhir)
│   ├── eval.ml         # Tree-walking evaluator
│   ├── repl.ml         # REPL implementation
│   ├── arrow/          # Arrow C GLib FFI
│   ├── ffi/            # Foreign function interface
│   └── packages/       # Standard library
│       ├── base/       # Errors, NA, assertions
│       ├── core/       # Functional primitives
│       ├── math/       # Mathematical functions
│       ├── stats/      # Statistical functions
│       ├── dataframe/  # CSV I/O, DataFrame ops
│       ├── colcraft/   # Data verbs, window functions
│       ├── pipeline/   # Pipeline introspection
│       └── explain/    # Introspection tools
├── docs/               # Documentation
├── examples/           # Example T programs
├── tests/              # Test suite
└── flake.nix           # Nix development environment
```

## Building from Source

```bash
# Build
dune build

# Run tests
dune runtest

# Execute REPL
dune exec src/repl.exe

# Build specific target
dune build src/repl.exe
```

See [Development Guide](docs/development.md) for details.

## Contributing

We welcome contributions! Please see our [Contributing Guide](docs/contributing.md) for:

- [Code of Ethics](docs/code-of-ethics.md)
- How to submit issues and pull requests
- Coding standards
- Testing requirements

## License

T is licensed under the [European Union Public License v1.2](LICENSE).

## Links

- **Website**: [tstats-project.org](https://tstats-project.org)
- **Repository**: [github.com/b-rodrigues/tlang](https://github.com/b-rodrigues/tlang)
- **Documentation**: [tstats-project.org](https://tstats-project.org)

---

*Built with curiosity, designed for reproducibility.*
