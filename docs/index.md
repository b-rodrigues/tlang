# T — The Orchestration Engine for Polyglot Data Science

**T** is an experimental orchestration engine designed for declarative, reproducible pipelines. It provides a functional Domain-Specific Language (DSL) that coordinates R, Python, and Shell nodes—with Julia support planned—within a Nix-managed infrastructure.

Unlike traditional scripting languages, T is built to be a **specifications-ready engine**, making data analysis **explicit, inspectable, and pipeline-oriented**. This unique architecture ensures that humans and LLMs can collaborate on defining high-level intent while T handles the low-level orchestration and environmental consistency.

**Status:** Version 0.51.4 "Sangoku", latest stabilization release.

---

## The Polyglot Pipeline

T's core strength is its **mandatory pipeline architecture**. To execute code in T, you typically define it as a series of nodes in a directed acyclic graph (DAG). T handles the "glue":

```t
-- A reproducible polyglot pipeline
p = pipeline {
  -- 1. Load data natively in T (CSV backend)
  data = node(
    command = read_csv("examples/sample_data.csv") |> filter($age > 25),
    serializer = "csv"
  )
  
  -- 2. Train a statistical model in R (using the rn() wrapper)
  model_r = rn(
    command = <{ lm(score ~ age, data = data) }>,
    serializer = "pmml",
    deserializer = "csv"
  )
  
  -- 3. Predict natively in T (no R/Python runtime needed for evaluation!)
  predictions = node(
    command = data |> mutate($pred = predict(data, model_r)),
    deserializer = "pmml"
  )

  -- 4. Generate a shell report
  report = shn(command = <{
    printf 'R model results cached at: %s\n' "$T_NODE_model_r/artifact"
  }>)
}

-- Build the pipeline into reproducible Nix artifacts
build_pipeline(p)
```

## What is T?

T is not designed to replace your existing tools; it is designed to **orchestrate** them. It addresses the "dependency drift" and "works on my machine" syndrome by making **Nix mandatory**.

- **Orchestration, Not Invention**: Use R for its statistics, Python for its machine learning, and T to ensure they always talk to each other correctly via high-performance formats like Apache Arrow.
- **Strictly Functional & Immutable**: T eliminates side effects and mutable state. If `a = 1 / 0`, then `a` is an `Error` value, not an exception. Logic is auditable and predictable.
- **Mandatory Reproducibility**: Every node in a T pipeline runs in its own sandboxed Nix environment. T automatically detects dependencies and ensures that if a node's inputs haven't changed, its results are pulled from the cache.
- **AI-Native Design**: Through features like `intent` blocks and structured metadata, T is built for a future where humans and AI collaborate on complex data workflows.

---

## Foreign Language Nodes & Deserialization

When you define a node using `node()`, `rn()` (R), `pyn()` (Python), or `shn()` (Shell)—with Julia support planned—T treats the result as a first-class **Node** object. These objects transition through two main states:

1.  **Unbuilt Node**: A specification of what to run (command, runtime, environment variables).
2.  **Computed Node**: After `build_pipeline()`, the node points to a concrete, immutable artifact in the Nix store.

### Automatic Deserialization

When you call `read_node("node_name")` in the REPL, T looks at the node's **serializer** and attempts to automatically load the data back into the T environment:

| Serializer | Resulting T Type | Backend |
| :--- | :--- | :--- |
| `default` / `serialize` | Varies | Native T binary serialization |
| `arrow` | `DataFrame` | Apache Arrow IPC (zero-copy) |
| `csv` | `DataFrame` | Native CSV parser |
| `json` | `Dict` / `List` | JSON parser |
| `pmml` | `Model` | Native T model evaluator |

### Looking into the "Entrails"

If a node's serializer is not supported for automatic deserialization, `read_node()` returns the **Computed Node object** itself. This object contains all the metadata necessary to load the artifact manually or inspect its provenance.

You can use `explain()` to look inside a built node:

```t
-- Example: Inspecting a built R node
> model_node = p.model_r
> explain(model_node)
{
  `kind`: "computed_node",
  `name`: "model_r",
  `runtime`: "R",
  `path`: "/nix/store/...-model_r/artifact",
  `serializer`: "pmml",
  `class`: "lm",
  `dependencies`: ["data"]
}
```

The `path` field is the "escape hatch"—it gives you the absolute path to the node's output in the Nix store. You can use this to start an external interpreter and inspect the file directly, or pass it to a custom loader like `read_parquet(model_node.path)`.

---

## Documentation: The Theoretical Foundation

- [Theoretical Paper: Reproducibility-First Programming Languages](theoretical_paper.html) — the core philosophy and design principles of T.

### Getting Started
- [Getting Started Guide](getting-started.html) — first steps with T
- [Installation Guide](installation.html) — detailed setup with Nix
- [Language Overview](language_overview.html) — types, syntax, functions, and standard library
- [Type System](type-system.html) — detailed guide to T's type hierarchy and semantics
- [Numerical Arrays](arrays.html) — tutorial on N-dimensional arrays and linear algebra
- [Editor Support](editors.html) — setup guide for Vim, Emacs, and VS Code

### User Guides
- [API Reference](api-reference.html) — complete function reference by package
- [Data Manipulation Examples](data_manipulation_examples.html) — practical examples with core data verbs
- [Factors & Categorical Data](factors.html) — factor creation, level ordering, and `fct_*` helpers
- [String Manipulation](string_manipulation.html) — naming rules, examples, and exceptions for text helpers
- [Pipeline Tutorial](pipeline_tutorial.html) — step-by-step guide to T's pipeline model
- [Literate Programming with Quarto](literate-programming-quarto.html) — rendering reports from pipelines
- [Statistical Models](models.html) — linear regression, GLMs, and broom-style output
- [Plotting & Visualization](plotting.html) — ggplot2, matplotlib, and visual metadata capture
- [PMML Tutorial](pmml_tutorial.html) — move supported models between R, Python, and T
- [Handling Dates](handling_dates.html) — parsing, extraction, and date arithmetic
- [Error Handling Guide](error-handling.html) — error patterns and recovery strategies
- [Comprehensive Examples](examples.html) — real-world analysis patterns
- [T Pipeline Demos](demos.html) — interactive reports for T demo projects

### Advanced Topics
- [Reproducibility Guide](reproducibility.html) — Nix integration and reproducible workflows
- [LLM Collaboration](llm-collaboration.html) — intent blocks and AI-assisted development
- [Quotation & Metaprogramming](quotation.html) — capturing and generating code
- [Statistical Formulas](formulas.html) — formula syntax for modeling
- [Performance](performance.html) — Arrow backend and optimization
- [Performance Analysis](performance_analysis.html) — in-depth analysis of T's performance metrics
- [Composable Lenses](lens.html) — functional updates for nested structures

### Developer Resources
- [Architecture](architecture.html) — language design and implementation
- [Contributing Guide](contributing.html) — how to contribute to T
- [Development Guide](development.html) — building, testings, and debugging
- [Project Development](project_development.html) — managing T projects and workspaces
- [Package Development Guide](package_development.html) — creating and publishing T packages

### Reference & Support
- [Function Reference](reference/index.html) — exhaustive per-function guide
- [FAQ](faq.html) — frequently asked questions
- [Troubleshooting](troubleshooting.html) — common issues and solutions
- [Changelog](changelog.html) — history of changes and releases
