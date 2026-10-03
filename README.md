# T — Reproducible Pipelines for Polyglot Data Science

[![Chat on Matrix](https://img.shields.io/badge/Chat%20on-Matrix-000?logo=matrix&logoColor=white)](https://matrix.to/#/#tproject:matrix.org)
[![License: EUPL v1.2](https://img.shields.io/badge/License-EUPL%20v1.2-blue.svg)](LICENSE)
[![Status: Beta](https://img.shields.io/badge/Status-Beta%200.55.5%20%22L%27Ultime%20combat%22-blue.svg)](https://tstats-project.org/changelog.html)
[![Built with Nix](https://img.shields.io/badge/built%20with-Nix-5277C3.svg?logo=nixos&logoColor=white)](https://nixos.org)
[![Documentation](https://img.shields.io/badge/docs-tstats--project.org-informational.svg)](https://tstats-project.org)
[![CI](https://github.com/b-rodrigues/tlang/actions/workflows/unit-tests.yaml/badge.svg)](https://github.com/b-rodrigues/tlang/actions)
[![OCaml](https://img.shields.io/badge/OCaml-5.x-EC6813.svg?logo=ocaml&logoColor=white)](https://ocaml.org)

**Use Julia, Python, and R for what they’re really good at — whatever that is for you. T orchestrates them.**

Simulations in Julia, ML in Python, statistics in R — or the exact opposite. It doesn't matter how you divide the labor: the hard part of polyglot data science was never the languages, it was the fragile seam between them.

A language for the LLM era, T is designed to be piloted by both humans and AI models. It gives you one hermetic dependency graph where your tools communicate without glue and execute consistently through space and time: on your laptop today, on a cluster tomorrow, and five years from now without bitrot.

---

### Quick Setup (For People in a Hurry)

1. **[Install Nix](docs/nix-installation.md)** (installs Nix and configures the `rstats-on-nix` cache in one step):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
     sh -s -- install --no-confirm --extra-conf "
   trusted-users = root $USER
   substituters = https://cache.nixos.org https://rstats-on-nix.cachix.org
   trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
   ```
2. **Try T immediately** in an ephemeral shell:
   ```bash
   nix shell --accept-flake-config github:b-rodrigues/tlang
   ```
3. **Scaffold a project** and enter its pinned environment:
   ```bash
   t init --project my_project && cd my_project && nix develop
   ```
*(See the [Nix Installation Guide](docs/nix-installation.md) and [Getting Started Tutorial](docs/getting-started.md) for full platform instructions).*

---

## Interactive Demo in 30 Seconds

Run `t demo` right in your terminal to see pipeline introspection, hermetic Nix builds, Arrow in-memory inspection, caching, and first-class error handling in action:

![T Interactive Demo](demo.gif)

---

## How It Looks in Practice

A complete analysis that simulates non-linear data in Julia, fits a gradient-boosted regressor in Python, plots ground truth vs predictions in R, and compiles a Quarto report:

![T pipeline with Julia, Python, and R code blocks, each with its own colors](demo-polyglot.svg)

*Colors show each runtime: the `jln` block is Julia, `pyn` is Python, `rn` is R.*

<details>
<summary>Show full code (copy and paste)</summary>

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
  plot = rn(
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

  -- 4. Render reproducible Quarto report
  report = node(script = "src/report.qmd", runtime = Quarto)
}

build_pipeline(p)
```

</details>

- **Zero manual I/O:** R returns the `ggplot` object directly; T's runner automatically renders and caches the visual artifact without `ggsave()`. DataFrames pass between nodes via Apache Arrow IPC (`^ipc`) without `read.csv()` or `to_csv()` glue.
- **No vendor lock-in (use standalone scripts):** You don't have to embed code in `<{ ... }>` blocks. Nodes accept external script files directly (`jln(script = "sim.jl")`, `pyn(script = "train.py")`, `rn(script = "plot.R")`). Your Julia, Python, and R scripts remain ordinary standalone files that your team can run or reuse anywhere with standard tooling.
- **First-class polyglot errors (no pipeline crashes):** If an error or exception occurs inside a node—whether in Python (`raise`), R (`stop()`), Julia (`error()`), or T (`error()`)—it does not crash the entire pipeline build. T captures the error at the sandbox boundary, serializes a structured `VError` artifact, and allows independent branches to complete. Downstream nodes can inspect the error with `read_node()` or `explain()`, or recover programmatically.
- **Literate reporting:** The Quarto node compiles `src/report.qmd` into an HTML or PDF report inside the Nix sandbox, directly embedding upstream metrics and figures.
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
4. **Polyglot soft-failures:** In conventional workflow engines, an uncaught exception in a single script aborts the entire DAG run. In T, errors are first-class values across all runtimes: failing nodes capture full tracebacks into structured `VError` artifacts while independent parallel branches continue uninterrupted.

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
| **Error resilience** | ❌ (Aborts run) | ❌ (Aborts run) | ❌ (Aborts run) | ❌ (Container exits) | ✅ (First-class polyglot soft-failures) |

---

## Workflow: From REPL Exploration to Audited DAG

You do not have to start with a complex graph.

1. **Explore interactively:** Use T's REPL or your native R/Python/Julia sessions inside the pinned project shell to inspect data.
2. **Wrap in `pipeline {}`:** When your analysis stabilizes, assign your steps to `jln()`, `pyn()`, or `rn()` nodes in a single `pipeline.t` file.
3. **Verify in milliseconds:** Run `t check --schema pipeline.t` to validate node dependencies and column names instantly—no builds triggered.
4. **Build and cache:** Run `t run pipeline.t`. Every step is built and cached in the Nix store.

---

## Fast Agent / LLM Collaboration

T shrinks the search space for AI coding assistants:
- **Sub-second reject loops:** `t check --json` runs instant schema and DAG validation in milliseconds, giving agents structured compiler feedback before triggering expensive builds.
- **Contract-first context:** Every project includes an optimized [AGENTS.md](AGENTS.md) so tools like Claude Code, Cursor, and Copilot understand valid node signatures on the first prompt.
- **Functional immutability:** Strict value semantics eliminate hidden global mutations across steps.

Every check emits structured JSON, not a stack trace:

```bash
$ t check --json pipeline.t
```
```json
{
  "error_class": "schema_mismatch",
  "node": { "id": "summary", "lang": "python" },
  "message": "Column 'mg' not found. Did you mean 'mpg'?",
  "caused_by": ["clean"],
  "suggested_fix": { "kind": "rename_column", "old_name": "mg", "new_name": "mpg" }
}
```

An agent can parse `error_class`, locate the failing `node`, trace `caused_by` upstream, and either apply the `suggested_fix` via `t fix`, or fix the root cause itself. Once `t check` is clean, `t run --json` streams NDJSON build events with root causes, and `t diff` reports the exact blast radius of a change.

See the **[Agent Pairing Tutorial](docs/agent-pairing-tutorial.md)** for the full loop end-to-end.

---

## Key Features

### Functional Safety & Errors
T is built on a "no-surprises" philosophy. **Errors are first-class values**, not exceptions. Functions return explicit `Error` types when something goes wrong (e.g., missing files, type mismatches), allowing you to handle them as data. If `a = 1 / 0`, then `a` is an `Error` value, not an exception. Overwriting `a` with `a = 2` will not work as T is immutable. Use `:=` to reassign a variable, or `rm(a)` to remove it from the environment entirely.

### Semantic Piping
T provides two types of pipes to manage complex data flows and error states:
- **Standard Pipe (`|>`)**: Designed for linear transformations. If the input is an **Error** value, `|>` **short-circuits** and skips the function call, automatically propagating the error forward. This prevents crashing and ensures that your functions only process valid data.
- **Maybe-Pipe (`?|>`)**: Designed for **error recovery**. Unlike the standard pipe, `?|>` **always forwards** the value—including Errors—to the next function. This allows you to write custom handlers that can inspect Errors and potentially recover from them.

### Dynamic Pattern Branching
Pipeline nodes can be dynamically expanded into multiple branches using `map_pattern(dep)` or `cross_pattern(...)`. Supports List, Vector, and DataFrame dependencies, auto-expansion on `build_pipeline`/`populate_pipeline`/composition builtins, and cross-runtime branch execution (T/R/Python/Julia) with JSON interchange. See the [Pipeline Materialization](docs/pipeline-materialization.md#pattern-based-branching) guide for details.

### Static DAG Conditionals
`node_when(condition, node_value)` includes or excludes a node from the DAG at pipeline construction time if the condition is falsy. `node_fork(cond1, val1, cond2, val2, ..., .default = ...)` selects the first matching branch. Both preserve Nix's acyclic build requirement.

### Introspection with `explain()`
T values and pipelines are highly introspectable. The **`explain`** package provides the `explain()` function, which can be called on any object to get a detailed summary of its structure, metadata, and status. It is the recommended way to "look inside" your data and nodes in the REPL.

### Technical Presentation & Language Architecture

For compiler engineers, programming language researchers, and systems architects interested in T's underlying formal semantics, AST design, process-isolated Nix execution engine, embedded PMML/ONNX model scoring, and composable optics:

👉 **Read the [Technical Presentation & Language Architecture Guide](docs/technical-presentation.md)**.

---

## Quick Start & Installation

T requires [Nix](docs/nix-installation.md) with flakes enabled. T is distributed via Nix to guarantee byte-for-byte reproducibility across operating systems.

We recommend using the **Determinate Systems Nix Installer** for the cleanest setup. See the [Nix Installation Guide](docs/nix-installation.md) for detailed platform-specific steps.

Start by launching an ephemeral shell that provides the `t` executable:

```bash
nix shell --accept-flake-config github:b-rodrigues/tlang
```

Bootstrap a new project:

```bash
t init --project my_project
```

Enter your project's reproducible development environment:

```bash
cd my_project
nix develop
```

This dev shell provides the `t` command alongside all declared R, Python, and Julia runtimes.

Edit `src/pipeline.t`, verify with `t check --schema src/pipeline.t`, and build:

```bash
t run src/pipeline.t
```

---

## Ecosystem & Standard Libraries

**Beta 0.55.5 "L'Ultime combat"** — The T runtime includes built-in packages inspired by the tidyverse for data wrangling before or alongside foreign nodes:

- **colcraft**: Core data manipulation and categorical data management (`filter`, `select`, `mutate`, `summarize`, `pivot_*`, `fct_*`).
- **chrono**: Comprehensive date and time handling (`ymd`, `floor_date`, `interval`).
- **strcraft**: Modern string manipulation (`str_replace`, `str_detect`, `str_split`).
- **lens**: Serializable, composable lenses for surgical updates to nested data and pipeline re-orchestration.
- **Native Arrow I/O**: High-performance reading and writing of `CSV`, `Parquet`, and `Arrow` (IPC/Feather) formats.
- **Pipeline Introspection**: Query execution graphs (`which_nodes`, `filter_node`, `errored_nodes`).

---

## Building from Source

```bash
git clone https://github.com/b-rodrigues/tlang.git
cd tlang
nix develop

# Build
dune build

# Run unit tests
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
- **[Agent Pairing Tutorial](docs/agent-pairing-tutorial.md)** — Interactive development with an AI agent
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
