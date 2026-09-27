# T — Nix Make for Polyglot Data Science

[![Chat on Matrix](https://img.shields.io/badge/Chat%20on-Matrix-000?logo=matrix&logoColor=white)](https://matrix.to/#/#tproject:matrix.org)
[![License: EUPL v1.2](https://img.shields.io/badge/License-EUPL%20v1.2-blue.svg)](LICENSE)
[![Built with Nix](https://img.shields.io/badge/built%20with-Nix-5277C3.svg?logo=nixos&logoColor=white)](https://nixos.org)
[![Documentation](https://img.shields.io/badge/docs-tstats--project.org-informational.svg)](https://tstats-project.org)
[![CI](https://github.com/b-rodrigues/tlang/actions/workflows/unit-tests.yaml/badge.svg)](https://github.com/b-rodrigues/tlang/actions)
[![OCaml](https://img.shields.io/badge/OCaml-5.x-EC6813.svg?logo=ocaml&logoColor=white)](https://ocaml.org)

**Simulate in Julia. Train in Python. Report in R. Pin the entire stack.**  
*T is a pipeline tool that coordinates R, Python, and Julia analyses in a single, content-addressed dependency graph. One file, bit-for-bit reproducible, zero reticulate or PyCall glue.*

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

## Workflow: From REPL Exploration to Audited DAG

You do not have to start with a complex graph.

1. **Explore interactively:** Use T's REPL or your native R/Python/Julia sessions inside the pinned project shell to inspect data.
2. **Wrap in `pipeline {}`:** When your analysis stabilizes, assign your steps to `jln()`, `pyn()`, or `rn()` nodes in a single `pipeline.t` file.
3. **Verify in milliseconds:** Run `t check --schema pipeline.t` to validate node dependencies and column names instantly—no builds triggered.
4. **Build and cache:** Run `t run pipeline.t`. Every step is built and cached in the Nix store.

---

## Fast Agent / LLM Collaboration

T is designed to eliminate hallucination in AI-assisted workflows:
- **Strictly immutable semantics:** No hidden state mutations or side effects.
- **Fast verification loop:** `t check --json` gives AI coding agents instant, machine-readable compiler diagnostics before running expensive builds.
- **Standard agent instructions:** Every project includes an optimized `AGENTS.md` so tools like Claude Code, Cursor, and Copilot write valid T pipelines on the first prompt.

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

### Property-Based Testing with `propcraft`
For hardening T's standard library and reusable packages, the **`propcraft`** package provides property-based testing: state an invariant and `prop_for_all(gen, property)` checks it over many generated inputs, reporting a deterministic shrunk counterexample on failure. Generators are structured Dicts (`prop_gen_int_range`, `prop_gen_df`, `prop_gen_string_from`, ...) and all draws use the seeded RNG, so `set_seed(n)` reproduces failures exactly.

```t
set_seed(42)
assert(prop_for_all(prop_gen_int_range(0, 100), \(x) x >= 0))
```

See the [Property-Based Testing guide](docs/property-testing.md) for details.

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

The T runtime includes built-in packages inspired by the tidyverse for data wrangling before or alongside foreign nodes:

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
