# T Programming Language

**T** is an experimental, reproducibility-first programming language for declarative data manipulation and statistical analysis. Inspired by R's tidyverse and OCaml's type discipline, T is designed for teams and researchers who want a small, focused, understandable language dedicated to data wrangling, statistics, and analysis—without general-purpose programming baggage.

[![License: EUPL v1.2](https://img.shields.io/badge/License-EUPL%20v1.2-blue.svg)](LICENSE)
[![Status: Alpha](https://img.shields.io/badge/Status-Alpha%200.1-orange.svg)](https://tstats-project.org)

## Quick Start

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
    |> mutate($age_group, \(row) if (row.age < 30) "young" else "mature")
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

**Alpha 0.1** — Syntax and semantics frozen. The language is functional and ready for exploratory use. Production use requires further testing and performance optimization.

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

- Code of conduct
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
