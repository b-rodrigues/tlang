# T — Nix Make for Polyglot Data Science

**Simulate in Julia. Train in Python. Report in R. Pin the entire stack.**

T is a pipeline orchestration engine and language that coordinates R, Python, and Julia analyses in a single, content-addressed dependency graph. One file, bit-for-bit reproducible, zero reticulate or PyCall glue.

Built on Nix, T integrates declarative environment management and deterministic builds at the language level. Every node runs in its own hermetic sandbox, and data moves seamlessly across languages via Apache Arrow IPC, ONNX, and PMML.

---

## The 30-Second Example

A complete analysis that runs a heavy simulation in Julia, trains a model in Python, and plots the results in R:

```t
p = pipeline {
  -- 1. Heavy numerical simulation in Julia (jln)
  sim_data = jln(
    command = <{
      using DataFrames
      # Fast numerical simulation or ODE solving
      simulate_panel(n_agents = 50_000, periods = 12)
    }>,
    serializer = ^arrow
  )

  -- 2. Train machine learning model in Python (pyn)
  model = pyn(
    command = <{
      from sklearn.ensemble import GradientBoostingRegressor
      X = sim_data.drop(columns=['y'])
      clf = GradientBoostingRegressor().fit(X, sim_data['y'])
      clf
    }>,
    deserializer = ^arrow,
    serializer = ^onnx
  )

  -- 3. Publication-quality figure & audit report in R (rn)
  report = rn(
    command = <{
      library(ggplot2)
      p <- ggplot(sim_data, aes(x = period, y = y)) +
        geom_line(color = "#2c3e50") +
        theme_minimal()
      ggsave(file.path(output_dir, "policy_report.png"), p)
    }>,
    deserializer = ^arrow
  )
}

build_pipeline(p)
```

Run it once: every node executes in its own hermetic sandbox.  
Run it again: all three nodes hit the local cache instantly.

---

## Why Polyglot Pipelines Break (And How T Fixes Them)

Most modern quantitative projects in research, central banks, official statistics, and regulated industries are polyglot by necessity:
- **Julia** is unmatched for raw numerical simulation, ODEs, and heavy optimization loops.
- **Python** is the standard for modern machine learning and deep learning tooling.
- **R** remains the gold standard for survey statistics, econometrics, and publication-ready reporting.

Connecting them today forces you to choose between three bad options:

| The Status Quo | The Failure Mode |
|---|---|
| **In-process FFI (`reticulate`, `PyCall`, `RCall`)** | Shared memory between multiple runtimes with competing garbage collectors and conflicting OpenMP/BLAS threads causes unexplained segfaults. Upgrading one runtime breaks the other. |
| **Ad-hoc Bash scripts & CSVs** | No caching: tweaking a title in an R ggplot re-runs your 3-hour Julia simulation. Column types and missing values silently mutate during CSV export. |
| **Chained Docker containers** | Huge container images, slow local development, impossible for an analyst to inspect or debug interactively on a laptop. |

### How T handles the seam:

1. **Process-level isolation:** Each foreign language node runs in its own isolated process. Julia's memory cannot corrupt R; Python's C-extensions cannot conflict with Julia's OpenMP threads.
2. **First-class data exchange:** Data passes between nodes using Apache Arrow IPC (`^arrow`) and standard model serialization (`^onnx`, `^pmml`, `^csv`). No custom serialization glue scripts.
3. **One pinned environment:** Under the hood, Nix locks your R packages, Python wheels, Julia depot, and underlying system C/Fortran libraries in one declarative manifest. If it runs today, it runs byte-for-byte identically in 2030.

---

## How T Compares

| Feature | {targets} | Snakemake | Docker | **T** |
|---|:---:|:---:|:---:|:---:|
| **Language focus** | R first | Python / CLI | Any | **R + Python + Julia** |
| **Cross-language glue** | Ad-hoc / `reticulate` | Shell scripts | Manual scripts | **Native (`^arrow`, `^onnx`)** |
| **Node caching** | Content-addressed (R) | Timestamp / file hash | Layer-based | **Content-addressed (all nodes)** |
| **System library locking** | ❌ (Delegates to host) | ❌ (Conda optional) | ✅ (Per image) | ✅ (Hermetic Nix sandbox) |
| **Local interactive inspect** | ✅ (`tar_read()`) | ❌ | ❌ | ✅ (`read_node()`) |

---

## Foreign Language Nodes & Deserialization

When you define a node using `node()`, `rn()` (R), `pyn()` (Python), `jln()`
(Julia), or `shn()` (Shell), T treats the result as a first-class **Node**
object. These objects transition through two main states:

1.  **Unbuilt Node**: A specification of what to run (command, runtime, environment variables).
2.  **Computed Node**: After `build_pipeline()`, the node points to a concrete,
    immutable artifact in the Nix store.

### Automatic (De)serialization

When you call `read_node(p.node_name)` in the REPL, T looks at the node's
**serializer** and attempts to automatically load the data back into the T
environment:

| Serializer | Resulting T Type | Backend |
| :--- | :--- | :--- |
| `default` / `serialize` | Varies | Native T binary serialization |
| `arrow` | `DataFrame` | Apache Arrow IPC (zero-copy) |
| `csv` | `DataFrame` | Native CSV parser |
| `json` | `Dict` / `List` | JSON parser |
| `pmml` | `Model` | Native T model evaluator |

### Inspecting Built Nodes with `explain()`

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

The `path` field is the escape hatch: it gives you the absolute path to the
node's output in the Nix store. You can inspect the artifact directly or pass it to external tools.

---

## Documentation: The Theoretical Foundation

- [Theoretical Paper: Reproducibility-First Programming Languages](theoretical_paper.html) — the core philosophy and design principles of T.

### Getting Started
- [Getting Started Guide](getting-started.html) — first steps with T
- [Your First Pipeline](first-pipeline.html) — declare R, Python, and Julia packages, run `t update`, and build a hello-world pipeline
- [Installing Nix for T](nix-installation.html) — recommended Determinate Systems installer and setup
- [Language Overview](language_overview.html) — types, syntax, functions, and standard library
- [Type System](type-system.html) — detailed guide to T's type hierarchy and semantics
- [Numerical Arrays](arrays.html) — tutorial on N-dimensional arrays and linear algebra
- [Editor Support](editors.html) — setup guide for Vim, Emacs, VS Code, and the Atelier TUI IDE

### User Guides
- [API Reference](api-reference.html) — complete function reference by package
- [Data Manipulation Examples](data_manipulation_examples.html) — practical examples with core data verbs
- [Data I/O & Formats](data-formats.html) — loading and saving CSV, Parquet, and Arrow IPC files
- [Factors & Categorical Data](factors.html) — to_factor creation, level ordering, and `fct_*` helpers
- [String Manipulation](string_manipulation.html) — naming rules, examples, and exceptions for text helpers
- [Pipeline Tutorial](pipeline_tutorial.html) — step-by-step guide to T's pipeline model
- [The Pipe Operator](pipes.html) — `|>` forwarding semantics and short-circuiting
- [Serializers in T](serializers.html) — first-class `^serializer` system for data interchange and materialization
- [Agent Pairing Tutorial](agent-pairing-tutorial.html) — building a T pipeline interactively with an AI agent
- [Advanced Pipeline Tutorial](advanced-pipeline-tutorial.html) — node manipulation, set operations, DAG transformations, composition, and validation
- [Pipeline Materialization & Nix Orchestration](pipeline-materialization.html) — building pipelines into reproducible Nix artifacts, orchestration, archives, CI/CD, branching, and custom flakes
- [Literate Programming with Quarto](literate-programming-quarto.html) — rendering reports from pipelines
- [Statistical Models](models.html) — linear regression, GLMs, and broom-style output
- [Plotting & Visualization](plotting.html) — ggplot2, matplotlib, and visual metadata capture
- [PMML Tutorial](pmml_tutorial.html) — move supported models between R, Python, and T
- [Handling Dates](handling_dates.html) — parsing, extraction, and date arithmetic
- [Error Handling Guide](error-handling.html) — error patterns and recovery strategies
- [Comprehensive Examples](examples.html) — real-world analysis patterns
- [T Pipeline Demos](demos.html) — interactive reports for T demo projects
- [Magic Commands](magic-cmds.html) — REPL-only `%` shortcuts (`%cd`, `%env`, and more)
- [External Helper Packages](external-packages.html) — reading T artifacts from R, Python, and Julia

### Advanced Topics
- [Reproducibility Guide](reproducibility.html) — Nix integration and reproducible workflows
- [LLM Collaboration](llm-collaboration.html) — intent blocks and AI-assisted development
- [Quotation & Metaprogramming](quotation.html) — capturing and generating code
- [Statistical Formulas](formulas.html) — formula syntax for modeling
- [Performance](performance.html) — Arrow backend and optimization
- [Performance Analysis](performance_analysis.html) — in-depth analysis of T's performance metrics
- [Composable Lenses](lens.html) — functional updates for nested structures
- [Nix Build Options & Orchestration](nix-options.html) — passing low-level nix arguments to the build

### Developer Resources
- [Architecture](architecture.html) — language design and implementation
- [Contributing Guide](contributing.html) — how to contribute to T
- [Code of Ethics](code-of-ethics.html) — principles and values for the T community
- [Development Guide](development.html) — building, testings, and debugging
- [Project Development](project_development.html) — managing T projects and workspaces
- [Package Development Guide](package_development.html) — creating and publishing T packages

### Reference & Support
- [Function Reference](reference/index.html) — exhaustive per-function guide
- [FAQ](faq.html) — frequently asked questions
- [Troubleshooting](troubleshooting.html) — common issues and solutions
- [Changelog](changelog.html) — history of changes and releases
