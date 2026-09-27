# T — Reproducible Pipelines for Polyglot Data Science

**Use Julia, Python, and R for what they’re really good at — whatever that is for you. T orchestrates them.**

Simulations in Julia, ML in Python, statistics in R — or the exact opposite. It doesn't matter how you divide the labor: the hard part of polyglot data science was never the languages, it was the fragile seam between them.

A language for the LLM era, T is designed to be piloted by both humans and AI models. It gives you one hermetic dependency graph where your tools communicate without glue and execute consistently through space and time: on your laptop today, on a cluster tomorrow, and five years from now without bitrot.

---

## The 30-Second Example

A complete analysis that simulates non-linear data in Julia, fits a gradient-boosted regressor in Python, and plots ground truth vs predictions in R:

```t
p = pipeline {
  -- 1. Simulate non-linear DGP in Julia (seeded)
  sim_data = jln(
    command = <{
      using Random, DataFrames
      Random.seed!(42)

      t = 1:500
      shock = cumsum(randn(500))
      DataFrame(time = t, shock = shock, signal = sin.(t ./ 20) .+ shock .* 0.2)
    }>,
    serializer = ^ipc
  )

  -- 2. Train non-linear model & predict in Python (scikit-learn)
  predictions = pyn(
    command = <{
from sklearn.ensemble import HistGradientBoostingRegressor

X = sim_data[['time', 'shock']]
y = sim_data['signal']
model = HistGradientBoostingRegressor(random_state=42).fit(X, y)
sim_data['pred'] = model.predict(X)
sim_data
    }>,
    deserializer = [sim_data: ^ipc],
    serializer = ^ipc
  )

  -- 3. Publication figure in R (ggplot2)
  report = rn(
    command = <{
      library(ggplot2)

      ggplot(predictions, aes(x = time)) +
        geom_point(aes(y = signal), alpha = 0.3, color = "#7f8c8d") +
        geom_line(aes(y = pred), color = "#e74c3c", linewidth = 1) +
        labs(title = "Julia Simulation + Python ML Predictions", y = "Value") +
        theme_minimal()
    }>,
    deserializer = [predictions: ^ipc]
  )
}

build_pipeline(p)
```

- **Zero manual I/O:** R returns the `ggplot` object directly; T's runner automatically renders and caches the visual artifact without `ggsave()`. DataFrames pass between nodes via Apache Arrow IPC (`^ipc`) without `read.csv()` or `to_csv()` glue.
- **Hermetic sandboxes:** Every node executes in an isolated Nix sandbox with pinned runtimes.
- **Seeded & cached:** Julia and Python draws are explicitly seeded. Unchanged nodes resolve instantly from the content-addressed store.

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
2. **First-class data exchange:** Data passes between nodes using Apache Arrow IPC (`^ipc`) and standard model serialization (`^onnx`, `^pmml`, `^csv`). No custom serialization glue scripts.
3. **One pinned environment:** Under the hood, Nix locks your R packages, Python wheels, Julia depot, and underlying system C/Fortran libraries in one declarative manifest. When paired with seeded execution, your pipeline builds and executes deterministically across machines.

---

## How T Compares

| Feature | {targets} | {rixpress} | Snakemake | Docker (packaging only) | **T** |
|---|:---:|:---:|:---:|:---:|:---:|
| **Interface & Engine** | R package (`_targets.R`), host environment | R package API, Nix engine | Python / CLI DSL, Conda/host | Container image, Docker daemon | **Dedicated pipeline language, Nix engine** |
| **Cross-language seam** | R-native (polyglot is bolted on) | R-native (Python nodes via `rixpress` helpers) | Shell scripts & CLI wrappers | Manual entrypoints & volume mounts | **Process-isolated IPC across R, Python, and Julia** |
| **Intermediate I/O** | Automatic | Automatic | Manual file paths | Manual volumes & files | **Automatic (zero-boilerplate boundary transfer)** |
| **Node caching** | Content-addressed (R) | Content-addressed (R) | Timestamp / file hash | Docker build layer cache | **Content-addressed (all nodes)** |
| **System library locking** | ❌ (Delegates to host) | ✅ (Hermetic Nix) | ⚠️ (Optional Conda) | ✅ (Per image) | ✅ (Hermetic per-node Nix sandbox) |
| **Interactive inspection** | ✅ (`tar_read()`) | ✅ (`read_node()`) | ⚠️ (File inspect only) | ❌ (Container attach) | ✅ (`read_node()`, `explain()`) |

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
- [Technical Presentation](technical-presentation.html) — DSL design, formal semantics, Arrow IPC, and Nix sandboxing architecture
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
