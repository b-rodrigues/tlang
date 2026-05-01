# T Orchestration Engine

[![Chat on Matrix](https://img.shields.io/badge/Chat%20on-Matrix-000?logo=matrix&logoColor=white)](https://matrix.to/#/#tproject:matrix.org)
[![License: EUPL v1.2](https://img.shields.io/badge/License-EUPL%20v1.2-blue.svg)](LICENSE)
[![Status: Beta](https://img.shields.io/badge/Status-Beta%200.51.5%20%22Sangoku%22-blue.svg)](https://tstats-project.org/changelog.html)
[![Documentation](https://img.shields.io/badge/docs-tstats--project.org-informational.svg)](https://tstats-project.org/api-reference.html)
[![Built with Nix](https://img.shields.io/badge/built%20with-Nix-5277C3.svg?logo=nixos&logoColor=white)](https://nixos.org)
[![CI](https://github.com/b-rodrigues/tlang/actions/workflows/unit-tests.yaml/badge.svg)](https://github.com/b-rodrigues/tlang/actions)
[![OCaml](https://img.shields.io/badge/OCaml-5.x-EC6813.svg?logo=ocaml&logoColor=white)](https://ocaml.org)

**T** is an experimental **orchestration engine** designed for **reproducible, polyglot data science**. As a functional, immutable DSL (domain-specific language), T coordinates R, Python, and Shell scripts into **Pipelines** that are managed as first-class objects. By leveraging **Nix** as its underlying build system, T ensures ironclad reproducibility and automated dependency management across your entire workflow.

The engine is built for seamless interoperability: you can manipulate objects defined in foreign-language nodes directly from within the T environment. Data conversion is handled transparently for common types, and T offers the flexibility to define custom serializers for complex interchanges—allowing you to leverage the strengths of each language without ever leaving the T runtime.

### The Polyglot Orchestrator

T's core strength is its **mandatory pipeline architecture**. It treats R scripts, Python models, and Shell commands as first-class nodes in a directed acyclic graph (DAG). T handles the "glue":
- **Nix-Powered Sandboxing**: Each node runs in its own reproducible environment.
- **High-performance Data Transfer**: Move DataFrames between R, Python, and T using Apache Arrow IPC via the Nix store.
- **Native Model Evaluation**: Train models in R/Python and evaluate them natively in T via PMML (linear models, decision trees, random forests, and boosted trees like **XGBoost** and **LightGBM**).
- **Model Interchange & Orchestration**: Use `^onnx` for model portability across Python and R nodes with T-native metadata orchestration.

```t
-- A reproducible polyglot pipeline
p = pipeline {
  -- 1. Load data natively in T (using the ^csv serializer)
  -- The ^ prefix identifies a first-class serializer in the T registry.
  data = node(
    command = read_csv("examples/sample_data.csv") |> filter($age > 25),
    serializer = ^csv
  )
  
  -- 2. Train a statistical model in R (using the rn() wrapper)
  model_r = rn(
    command = <{ lm(score ~ age, data = data) }>,
    serializer = ^pmml,
    deserializer = ^csv
  )
  
  -- 3. Predict natively in T (no R/Python runtime needed!)
  predictions = node(
    command = data |> mutate($pred = predict(data, model_r)),
    deserializer = ^pmml
  )

  -- 4. Generate a shell report
  report = shn(command = <{
    printf 'R model results cached at: %s\n' "$T_NODE_model_r/artifact"
  }>)
}

-- Build the pipeline into reproducible Nix artifacts
build_pipeline(p)
```

ONNX is also available as a first-class serializer:

```t
p = pipeline {
  model_py = pyn(
    command = <{
      from sklearn.linear_model import LogisticRegression
      clf = LogisticRegression().fit(X, y)
      clf
    }>,
    serializer = ^onnx
  )

  scored = pyn(
    command = <{
      session = model_py
      session
    }>,
    deserializer = ^onnx
  )
}
```

## Why T?

Data science projects often suffer from "dependency drift" and "works on my machine" syndrome. T eliminates these by making **Nix mandatory**. 

- **Orchestration, Not Invention**: T doesn't aim to replace R or Python. It aims to coordinate them. Use R for its stats, Python for its ML, and T to ensure they always talk to each other correctly.
- **Strictly Functional**: No loops, no mutable variables, and explicit `NA` handling. This reduces the "hallucination surface" for AI-assisted coding and makes logic easier to audit.
- **Mandatory Pipelines**: To run a script in T, you *must* define it as a pipeline. This forces you to move away from spaghetti scripts and toward a documented, cacheable architecture. Interactive line-by-line exploration is always possible in the **REPL**, however.

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

## AI-First Development

T is designed to treat AI agents as first-class collaborators. Its strictly functional, immutable syntax and explicit error handling significantly reduce the "hallucination surface" for LLMs.

When you initialize a new T project, the CLI prompts you to select an **AI Agent Onboarding Level** (Small, Medium, Full, or Huge). T then automatically generates:
- **`AGENTS.md`**: A project-specific onboarding guide for LLMs.
- **`T-LANGUAGE-REFERENCE.md`**: A tiered language reference tailored to the project's complexity and the agent's context window.

This ensures that any AI assistant you pair-program with has the exact technical context required to be productive immediately.

## Key Features

### Functional Safety & Errors
T is built on a "no-surprises" philosophy. **Errors are first-class values**, not exceptions. Functions return explicit `Error` types when something goes wrong (e.g., missing files, type mismatches), allowing you to handle them as data. If `a = 1 / 0`, then `a` is an `Error` value, not an exception. Overwriting `a` with `a = 2` will not work as T is immutable. Use `:=` to reassign a variable, or `rm(a)` to remove it from the environment entirely.

### Semantic Piping
T provides two types of pipes to manage complex data flows and error states:
- **Standard Pipe (`|>`)**: Designed for linear transformations. If the input is an **Error** value, `|>` **short-circuits** and skips the function call, automatically propagating the error forward. This prevents crashing and ensures that your functions only process valid data.
- **Maybe-Pipe (`?|>`)**: Designed for **error recovery**. Unlike the standard pipe, `?|>` **always forwards** the value—including Errors—to the next function. This allows you to write custom handlers that can inspect Errors and potentially recover from them.

### Introspection with `explain()`
T values and pipelines are highly introspectable. The **`explain`** package provides the `explain()` function, which can be called on any object to get a detailed summary of its structure, metadata, and status. It is the recommended way to "look inside" your data and nodes in the REPL.

---

## Quick Start & Installation

T requires [Nix](docs/nix-installation.md) with flakes enabled. T is distributed exclusively via Nix. Because Nix is mandatory for T's reproducibility and pipeline architecture, it is the only supported installation method and will remain so.

We recommend using the [Determinate Systems Nix Installer](https://install.determinate.systems/nix) for the best experience. See the [Nix Installation Guide](docs/nix-installation.md) for detailed platform-specific steps.

Start by launching a temporary shell that provides the `t` executable:

```bash
nix shell github:b-rodrigues/tlang
```

This drops you into an ephemeral environment with `t` available on your `PATH`.  
You can now bootstrap a new project:

```bash
t init --project my_t_project
```

You will be prompted to enter basic project information, including the **AI Agent Context Level** (Small, Medium, Full, or Huge) which generates tailored reference documentation for LLMs. When finished, leave the temporary shell:

```bash
exit
```

This creates a new directory (e.g. `my_t_project/`) containing the necessary project files.  
The most important file is `tproject.toml`. This file declares your project's dependencies. Dependencies must be explicitly listed here, as they are used by the project-specific flake to provide a fully reproducible environment.

You can now start working on your project by editing `src/pipeline.t`. 

> [!IMPORTANT]
> **Pipelines are Mandatory**: To execute a script (e.g., via `t run src/pipeline.t`), your code **must** be wrapped in a `pipeline { ... }` block and built using `build_pipeline(p)`. This ensures reproducibility and allows T to optimize execution.

If you have a sequence of commands you've tested in the REPL, you can easily wrap them in a pipeline (or even ask an LLM to do it for you!). 

### Recommended Workflow: Iterative Development
T encourages a "node-at-a-time" development cycle:
1. **Add Node-by-Node**: Add a new `node()` definition to your pipeline in `src/pipeline.t`.
2. **Execute**: Run your script (e.g., via `t run src/pipeline.t`) to build the derivations.
3. **Load & Inspect**: Load the node's output to inspect it via `read_node("node_name")` in the REPL to verify results.
4. **Run**: Once verified, run the entire pipeline and proceed to the next step.

```t
-- A basic pipeline in src/pipeline.t
p = pipeline {
  -- Load data (wrapped in a node for reproducibility)
  data = node(command = read_csv("data.csv", clean_colnames = true))

  -- Data manipulation using NSE (dollar-prefix) syntax
  result = node(command = data
    |> filter($age > 30)
    |> select($name, $age, $salary)
    |> arrange($age, "desc")
  )
  
  -- Analysis
  model = node(command = lm(data = data, formula = salary ~ age))
}

-- Execute and build the pipeline into reproducible Nix artifacts
build_pipeline(p)
```

See the [Installation Guide](docs/installation.md) for detailed setup instructions if you wish to build from source.

---

## Status & Missing Features

**Alpha 0.51.5 "Sangoku"** — The core syntax and functional semantics are stable. T is now a **reproducibility- and pipeline-first** language, with extensive native support for standard data manipulation verbs:

- **colcraft**: Core data manipulation and categorical data management (`filter`, `select`, `mutate`, `summarize`, `pivot_*`, `fct_*`, and more — heavily inspired by `dplyr`, `tidyr`, and `forcats`).
- **chrono**: Comprehensive date and time handling (`ymd`, `floor_date`, `interval`, etc. — inspired by `lubridate`).
- **strcraft**: Modern string manipulation (`str_replace`, `str_detect`, `str_split`, etc. — inspired by `stringr`).
- **lens**: Serializable, composable lenses for surgical updates to nested data and pipeline re-orchestration.
- **Native Arrow I/O**: High-performance reading and writing of `CSV`, `Parquet`, and `Arrow` (IPC/Feather) formats.
- **Polyglot & Metaprogramming**: First-class support for R, Python, and shell/CLI nodes, plus a robust metaprogramming layer (`expr`, `enquo`, `get`, `sym`).
- **Pipeline Introspection**: High-level tools for auditing and querying complex execution graphs (`which_nodes`, `filter_node`, `errored_nodes`).

What is currently missing:
* **Native T Plotting**: While T provides first-class metadata capture and headless rendering for **R (ggplot2)** and **Python (matplotlib, plotnine, plotly, altair)** objects, it does not yet have its own native charting library, and will likely never have one.
* **Complex Modeling**: While native `lm()` is available, specialized modeling should leverage R, Python, or future Julia nodes.
* **Ecosystem Growth**: We are building out the infrastructure for user-contributed packages through `t publish`.

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
│       ├── colcraft/   # Data verbs, window functions, factors
│       ├── chrono/     # Date and time handling
│       ├── strcraft/   # String manipulation
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
