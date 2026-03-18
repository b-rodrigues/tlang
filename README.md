# T Programming Language

[![License: EUPL v1.2](https://img.shields.io/badge/License-EUPL%20v1.2-blue.svg)](LICENSE)
[![Status: Alpha](https://img.shields.io/badge/Status-Alpha%200.51-orange.svg)](https://tstats-project.org)

**T** is an experimental, **polyglot-first** language designed for **data orchestration and reproducible analysis**. 

While many languages provide data manipulation libraries, T is uniquely built on the foundation of **Nix**. It doesn't just manage your code; it manages your entire environment—ensuring that your R, Python, and T code runs in the exact same pristine sandbox every time.

### The Polyglot Orchestrator

T's core strength is its **mandatory pipeline architecture**. It treats R scripts, Python models, and Shell commands as first-class nodes in a directed acyclic graph (DAG). T handles the "glue":
- **Nix-Powered Sandboxing**: Each node runs in its own reproducible environment.
- **Zero-Copy Data Transfer**: Move DataFrames between R, Python, and T using Apache Arrow.
- **Native Model Evaluation**: Train models in R/Python and evaluate them natively in T via PMML.

```t
-- A reproducible polyglot pipeline
p = pipeline {
  # 1. Load data natively in T (Arrow backend)
  data = node(command = read_csv("data.csv") |> filter($age > 18))
  
  # 2. Train a statistical model in R (using the rn() wrapper)
  model_r = rn(
    command = <{ lm(score ~ age + income, data = data) }>,
    serializer = "pmml"
  )
  
  # 3. Predict natively in T (no R/Python runtime needed for evaluation!)
  predictions = node(command = data 
    |> mutate($pred = predict(model_r, data))
  )

  # 4. Generate a shell report
  report = shn(command = <{
    printf 'R model results cached at: %s\n' "$T_NODE_model_r/artifact"
  }>)
}

# Build the pipeline into reproducible Nix artifacts
build_pipeline(p)
```

## Why T?

Data science projects often suffer from "dependency drift" and "works on my machine" syndrome. T eliminates these by making **Nix mandatory**. 

- **Orchestration, Not Invention**: T doesn't aim to replace R or Python. It aims to coordinate them. Use R for its stats, Python for its ML, and T to ensure they always talk to each other correctly.
- **Strictly Functional**: No loops, no mutable variables, and explicit `NA` handling. This reduces the "hallucination surface" for AI-assisted coding and makes logic easier to audit.
- **Mandatory Pipelines**: To run a script in T, you *must* define it as a pipeline. This forces you to move away from spaghetti scripts and toward a documented, cacheable architecture.

### Intent Blocks: A Thought Experiment

T features **`intent` blocks**—structured metadata embedded in code that describes the "why" and "how" of an analysis. 

> [!IMPORTANT]
> **Experimental Status**: `intent` blocks are currently a **thought experiment**. We are exploring how structured metadata can help LLMs understand code intent and how it can improve reproducibility audits. Their syntax and behavior are highly likely to change as we discover what "collaboration-first" code really looks like.

```t
intent {
  description: "Customer churn prediction",
  assumptions: ["Age > 18", "NA imputed with median"],
  requires: ["mtcars.csv"]
}
```

---

## Quick Start & Installation

T requires [Nix](https://nixos.org/) with flakes enabled. T is distributed exclusively via Nix. Because Nix is mandatory for T's reproducibility and pipeline architecture, it is the only supported installation method and will remain so.

Start by launching a temporary shell that provides the `t` executable:

```bash
nix shell github:b-rodrigues/tlang
```

This drops you into an ephemeral environment with `t` available on your `PATH`.  
You can now bootstrap a new project:

```bash
t init my_t_project
```

You will be prompted to enter basic project information. When finished, leave the temporary shell:

```bash
exit
```

This creates a new directory (e.g. `my_t_project/`) containing the necessary project files.  
The most important file is `tproject.toml`. This file declares your project's dependencies. Dependencies must be explicitly listed here, as they are used by the project-specific flake to provide a fully reproducible environment.

You can now start working on your project by editing `src/analysis.t`. You are free to rename this file or add additional source files as needed:

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

See the [Installation Guide](docs/installation.md) for detailed setup instructions if you wish to build from source.

---

## Status & Missing Features

**Alpha 0.51** — The core syntax and functional semantics are stable. T is now a **reproducibility- and pipeline-first** language, with support for **polyglot nodes** (R and Python) and **metaprogramming**. Current development focuses on refining the inter-language FFI and expanding the standard library.

What is currently missing:
* **Graphics and Plotting**: There is no native plotting library yet. Plots can be generated by R (ggplot2), Python (matplotlib), or Julia nodes.
* **Comprehensive Statistics**: While basic linear regression is native, more complex modeling is available by leveraging R or Python nodes.
* **User-contributed packages**: This is currently a major focus of development. Infrastructure for creating, documenting, and distributing user packages is being implemented and will be available from the **Beta** release onwards.
* Only a subset of mathematical functions and dplyr-like verbs are implemented.
* No random number generators.
* Only CSV files can be read and written.

You guessed it, I welcome contributions!

---

## Project Structure & Building

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

### Building from Source

```bash
git clone https://github.com/b-rodrigues/tlang.git
cd tlang
nix develop

# Build
dune build

# Run tests
dune runtest

# Execute REPL
dune exec src/repl.exe
```

See [Development Guide](docs/development.md) for details.

---

## Documentation

[**Full Documentation Website**](https://tstats-project.org)

- **[Getting Started](docs/getting-started.md)** — First steps with T
- **[Language Overview](docs/language_overview.md)** — Types, syntax, and core concepts
- **[Type System](docs/type-system.md)** — REPL vs strict mode, typed lambdas, and current limitations
- **[API Reference](docs/api-reference.md)** — Complete function reference
- **[Data Manipulation](docs/data_manipulation_examples.md)** — Practical examples with data verbs
- **[Pipeline Tutorial](docs/pipeline_tutorial.md)** — Step-by-step guide to pipelines
- **[Architecture](docs/architecture.md)** — Language design and implementation
- **[Contributing](docs/contributing.md)** — How to contribute to T

---

## Contributing & License

We welcome contributions! Please see our [Contributing Guide](docs/contributing.md) for:
- [Code of Ethics](docs/code-of-ethics.md)
- How to submit issues and pull requests
- Coding standards
- Testing requirements

T is licensed under the [European Union Public License v1.2](LICENSE).

---

*Built with curiosity, designed for reproducibility.*
