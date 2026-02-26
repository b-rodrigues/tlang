# T Programming Language

**T** is an experimental, **reproducibility- and pipeline-first** programming language for declarative data manipulation and statistical analysis. Built on the foundation of **Nix**, T is designed from the ground up to ensure that every analysis is a strictly defined, reproducible workflow. 

Inspired by R's tidyverse and OCaml's type discipline, T provides a small, focused core for data wrangling, but its true strength lies in its **mandatory pipeline architecture**.

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

### Pipelines are Mandatory

In T, non-interactive execution requires a pipeline. This is a deliberate design choice to eliminate ad-hoc, "spaghetti" scripts that plague data science projects. While the REPL allows for messy, iterative exploration, any script intended for production or sharing must be declared as a `pipeline`. 

This constraint ensures that your stabilization phase—moving from REPL to script—is an intentional act of documentation and architectural design.

### The Power of Polyglot Pipelines

T does not attempt to reinvent the wheel for every statistical model or machine learning algorithm. Instead, it acts as a **high-fidelity orchestration layer**. Because T uses Nix for build automation, it allows you to define nodes using different languages within the same pipeline:

- **Seamless Polyglotism**: Define an R node for data cleaning, a Python node for deep learning, and a T node for final reporting—all in one file.
- **PMML Model Interchange**: High-fidelity transfer of models from R/Python into T's native model evaluator.
- **Zero-Config Object Transfer**: Transparently pass data frames via Apache Arrow IPC between languages.
- **Nix-Powered Sandboxing**: Each node runs in a pristine, reproducible environment where dependencies are guaranteed to be present.

By using Nix as the engine, T provides a level of orchestration and reproducibility that general-purpose languages simply cannot match.

### A Modern Package Ecosystem

T is designed to be highly extensible. Users can easily create and share their own packages to add new functionality. Following the language's core philosophy, the package ecosystem is built entirely on Nix:

- **Environment-as-Code**: Every T package includes its own Nix flake. This means that a developer can simply run `nix develop` within a package's directory to get a fully configured development environment with all necessary tools (compilers, libraries, and dependencies) pre-installed.
- **Conflict-Free Dependency Management**: Since each package is isolated via Nix, you can use different versions of the same shared library in different packages without "dependency hell."

### But why not just use R or Python with Nix?

A valid question is: "Why not just use R or Python with Nix and a build automation tool?" The answer lies in human behavior and the limits of discipline.

Existing languages like R and Python have "bolted-on" reproducibility solutions. While tools like `rix` (for R) or `poetry2nix` (for Python) are excellent, they remain optional, ad-hoc interventions. In practice, unless a team has extreme discipline and high technical overhead, these solutions are often used inconsistently, late in the development cycle, or not at all.

T’s goal is to **force the usage of Nix from the very first line of code**. By providing a language where Nix isn't an option but the fundamental environment and distribution engine, we eliminate the need for ad-hoc discipline. A tool that leaves the user no choice but to be reproducible is the cleanest, most reliable way to ensure that "it works on my machine" actually means it will work on yours.

Furthermore, this coherence and mandatory declarative structure makes things significantly easier for Large Language Models (LLMs). As AI writes more of our analysis code, having a language with a small, focused core and a strictly declarative pipeline model reduces the "hallucination surface" and ensures that LLM-generated analysis is as reproducible and robust as human-written code.

Why “T”? The name is a nod to lineage and a bit of humor. R is a GPL-licensed 
reimplementation of S, and since T draws heavy inspiration from R, I thought calling it "T" would be
funny.

Why the EUPL? Because I love Europe and I love the GPL.

With all that said, this is a hobby project, 100% experimental, and made for fun. DO NOT USE IN PRODUCTION.

What is currently missing:

* **Graphics and Plotting**: There is no native plotting library yet. Plots can be generated by R (ggplot2), Python (matplotlib), or Julia nodes.
* **Comprehensive Statistics**: While basic linear regression is native, more complex modeling is available by leveraging R or Python nodes.
* **User-contributed packages**: This is currently a major focus of development. Infrastructure for creating, documenting, and distributing user packages is being implemented and will be available from the **Beta** release onwards.
* Only a subset of mathematical functions and dplyr-like verbs are implemented.
* No random number generators.
* Only CSV files can be read and written.

You guessed it, I welcome contributions!

## Quick Start

T is distributed exclusively via Nix. Because Nix is mandatory for T's reproducibility and pipeline architecture, it is the only supported installation method and will remain so.

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

- **🔒 Reproducibility-First**: Built on Nix flakes for bit-for-bit identical results across machines.
- **🔄 Mandatory Pipelines**: DAG-based computation is the only way to run scripts, preventing spaghetti code.
- **📦 Extensible Ecosystem**: User-contributed packages leverage Nix to provide isolated, zero-config development environments.
- **🌍 Polyglot Roadmap**: Designed to orchestrate R, Python, and Julia nodes with seamless data transfer.
- **📊 DataFrame Core**: High-performance tabular data with Apache Arrow backend and NSE syntax.
- **🔧 Functional Core**: Immutable values, closures, and explicit NA handling for predictable logic.
- **✨ Metaprogramming**: First-class quotation (`expr`), unquoting (`!!`, `!!!`), and evaluation (`eval`) for DSLs and code generation.
- **💾 Computed Nodes**: Evaluation results are persisted as immutable, content-addressed artifacts for maximum reproducibility.

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

## Polyglot Pipelines

T can orchestrate multiple languages within a single pipeline. Each `node()` defines a discrete step that can run in T, R, or Python, with Nix managing the environments.

```t
p = pipeline {
  -- Load data in T
  raw = node(
    command = read_csv("data.csv"),
    runtime = T
  )

  -- Process in R using dplyr
  cleaned = node(
    command = <{ raw |> dplyr::filter(age > 18) }>,
    runtime = R,
    functions = "utils.R"
  )

  -- Model in Python using scikit-learn
  model = node(
    command = py_model_script(cleaned),
    runtime = Python
  )
}

build_pipeline(p)
```

T handles the serialization and data transfer between languages transparently. DataFrames are passed via **Apache Arrow**, and models are exchanged using **PMML**, allowing T to perform native predictions on models trained in R or Python without runtime language dependencies.

## Metaprogramming (Quasiquotation)

T supports Lisp-style quotation for capturing and manipulating code. This is identical to R's `rlang` mechanics.

```t
-- Capture an expression
e = expr(1 + 2)

-- Unquote values (!!)
x = 10
e2 = expr(1 + !!x) -- expr(1 + 10)

-- Splicing lists (!!!)
vals = [1, 2, 3]
e3 = expr(sum(!!!vals)) -- expr(sum(1, 2, 3))

-- Evaluate
eval(e2) -- 11
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

### The Native Scope Challenge

The biggest challenge in developing T is deciding exactly what should be included natively in the language core and what should be left to polyglot nodes. For now, a basic set of mathematical functions and `dplyr`-like data verbs are implemented. It is likely that the native core of T will remain focused, providing the essentials for data wrangling, descriptive statistics, and linear regression, while encouraging users to reach for the broader R, Python, and Julia ecosystems for more specialized tasks.

## Status

**Alpha 0.5** — The core syntax and functional semantics are stable. T is now a **reproducibility- and pipeline-first** language, with support for **polyglot nodes** (R and Python) and **metaprogramming**. Current development focuses on refining the inter-language FFI and expanding the standard library.

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
