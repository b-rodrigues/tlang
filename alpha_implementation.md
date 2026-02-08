# T Alpha Implementation Plan

This document outlines a concrete, engineering-facing implementation plan to reach an **alpha version of the T programming language**. The goal of the alpha is not feature completeness, but a *coherent, end-to-end system* that validates T’s core design ideas: pipelines, tabular data, explicit semantics, and LLM-friendly structure.

The plan is structured in **phases**, each producing a usable and testable milestone. Engineers should be able to work largely in parallel within phases, but phases should be completed in order.

---

## Definition of Alpha

An alpha version of T must satisfy the following:

* A working interpreter with a stable core syntax
* A REPL capable of interactive exploration
* A tabular `DataFrame` type backed by Arrow
* A pipeline execution model with named nodes
* Basic data manipulation and summarization
* Deterministic execution with explicit errors
* Minimal but coherent standard library (`core`, `stats`, `colcraft`)

**Non-goals for alpha**:

* Performance tuning
* GPU / distributed execution
* Full statistical coverage
* Persistent package registry
* IDE integrations beyond basic tooling

---

## Phase 0 — Foundations (Language Skeleton)

**Objective**: Establish a minimal but stable language core.

### Deliverables

* OCaml project structure
* Lexer and parser
* AST definition
* Basic evaluator

### Tasks

* Define core syntax:

  * Literals (numbers, strings, booleans)
  * Vectors and lists
  * Dictionaries / records
  * Function definitions (`function(x) ...` and `\(x) ...`)
  * Assignment (`=`)
  * `if (...) ... else ...`
  * Pipe operator (`|>`)

* Implement:

  * Parser (Menhir or equivalent)
  * AST normalization
  * Simple evaluator (tree-walking is sufficient)

### Acceptance Criteria

* Can evaluate arithmetic expressions
* Can define and call functions
* Can pipe values through functions
* REPL can evaluate multi-line expressions

---

## Phase 1 — Values, Types, and Errors

**Objective**: Make semantics explicit and predictable.

### Deliverables

* Unified value representation
* Explicit missingness model
* Structured error system

### Tasks

* Define runtime value types:

  * Scalars
  * Vectors
  * DataFrame (placeholder initially)
  * Error values

* Implement missingness:

  * System `NA` with type tags
  * No implicit propagation

* Implement errors as values:

  * Symbolic error codes
  * Structured context payloads
  * No exceptions for user-visible errors

* Add `assert()` primitive

### Acceptance Criteria

* Errors can be inspected programmatically
* Missing values are explicit and typed
* Failed operations return errors, not crashes

---

## Phase 2 — Tabular Data and Arrow Integration

**Objective**: Introduce first-class tabular data.

### Deliverables

* Arrow-backed `DataFrame`
* CSV ingestion
* Schema introspection

### Tasks

* Integrate Apache Arrow OCaml bindings

* Define `DataFrame` abstraction:

  * Columns
  * Schema
  * Row count

* Implement:

  * `read_csv()`
  * `colnames()`
  * `nrow()`, `ncol()`
  * Column access by name

* Ensure immutability at the language level

### Acceptance Criteria

* Can load CSV into a DataFrame
* Can inspect schema and basic metadata
* DataFrames work as pipeline inputs

---

## Phase 3 — Pipelines and Execution Graph

**Objective**: Establish T’s core execution model.

### Deliverables

* Pipeline syntax
* DAG-based execution
* Named nodes with caching

### Tasks

* Implement `pipeline { ... }` construct

* Define pipeline nodes:

  * Name
  * Expression body
  * Dependencies

* Build execution graph:

  * Dependency resolution
  * Topological execution
  * Node-level caching

* Add basic introspection:

  * Node listing
  * Dependency graph

### Acceptance Criteria

* Pipelines execute deterministically
* Re-running skips unchanged nodes
* Nodes can be inspected individually

---

## Phase 4 — Core Data Verbs

**Objective**: Make data manipulation useful.

### Deliverables

* Minimal but coherent data API

### Tasks

Implement core verbs:

* `select()`
* `filter()`
* `mutate()`
* `arrange()`
* `group_by()`
* `summarize()`

Design constraints:

* No NSE or implicit column capture
* Explicit column references
* Grouped DataFrame object

### Acceptance Criteria

* Can express simple tidy-style pipelines
* Grouped operations behave predictably
* Errors are explicit for invalid operations

---


## **Revised Phase 5 — Numerical and Statistical Libraries**

**Objective**
Provide a clear, disciplined numerical foundation for T by separating **pure mathematical primitives** from **statistical summaries and models**.

Both libraries introduced in this phase are **autoloaded by default** and live under the `packages/` directory.

---

### Deliverables

* Owl-backed numerical backend
* Two default standard libraries:

  * **`math`** — pure numerical primitives
  * **`stats`** — statistical summaries and models

---

### Package Structure

```text
packages/
├── math/
│   ├── sqrt.t
│   ├── abs.t
│   ├── log.t
│   ├── exp.t
│   └── pow.t
└── stats/
    ├── mean.t
    ├── sd.t
    ├── quantile.t
    ├── cor.t
    └── lm.t
```

Both packages are loaded automatically at startup and are considered part of T’s **standard library**.

---

### Package Responsibilities

#### `math` package

Contains **pure, deterministic numerical functions** that:

* Operate on scalars or vectors
* Have no statistical interpretation
* Do not inspect distributions or tabular structure
* Are total or fail with explicit errors

Examples:

* `sqrt()`
* `abs()`
* `log()`
* `exp()`
* `pow()`

Rule of thumb:

> If the function would make sense in a calculator, it belongs in `math`.

---

#### `stats` package

Contains **statistical summaries and models** that:

* Operate on vectors or DataFrames
* Are sensitive to missing values
* Encode statistical meaning or assumptions
* May produce structured model objects

Examples:

* `mean()`
* `sd()`
* `quantile()`
* `cor()`
* `lm()` (linear regression)

Rule of thumb:

> If the function answers a question about data, it belongs in `stats`.

---

### Tasks

* Integrate Owl as the numerical backend
* Implement `math` functions as thin, pure wrappers around Owl
* Implement `stats` functions with:

  * Explicit NA handling
  * Structured error values for invalid inputs
  * Clearly documented assumptions (in code)
* Ensure all functions compose cleanly inside pipelines

---

### Acceptance Criteria

* `math` and `stats` functions are available without imports
* Users can fit and inspect a simple linear model using `lm()`
* Numerical and statistical functions integrate cleanly with pipelines
* NA handling and errors are explicit and inspectable

---

## Phase 6 — Intent Blocks and Tooling Hooks

**Objective**: Prepare for LLM-native workflows.

### Deliverables

* Intent block parsing
* Tooling metadata extraction

### Tasks

* Define intent block syntax (structured comments)

* Preserve intent blocks in AST

* Expose intent metadata via tooling API

* Implement `t explain`:

  * Schema
  * NA stats
  * Example rows

### Acceptance Criteria

* Intent blocks are parseable and retrievable
* Tooling can extract machine-readable context

---

## Phase 7 — REPL, CLI, and Packaging

**Objective**: Make T usable by humans.

### Deliverables

* CLI tool (`t`)
* Interactive REPL
* Minimal package layout

### Tasks

* Implement CLI commands:

  * `t repl`
  * `t run file.t`

* Improve REPL:

  * Multi-line input
  * Pretty-printing
  * Error display

* Define standard packages:

  * `core`
  * `stats`
  * `colcraft`

### Acceptance Criteria

* Users can install and run T
* REPL is stable and usable
* Standard packages load by default

---

## Phase 8 — Stabilization and Alpha Release

**Objective**: Produce a coherent alpha release.

### Deliverables

* Documentation
* Test coverage
* Example analyses

### Tasks

* Write:

  * Language overview
  * Pipeline tutorial
  * Data manipulation examples

* Add:

  * Unit tests for core semantics
  * Golden tests for pipelines

* Freeze syntax and semantics for alpha

### Acceptance Criteria

* End-to-end examples run reproducibly
* No known crashes in core workflows
* Clear roadmap beyond alpha

---

## Final Notes

This plan intentionally prioritizes **semantic clarity and architectural coherence** over feature breadth or performance. A successful alpha proves that T’s design is viable, understandable, and extensible — not that it solves every data science problem.

Engineers should treat this document as a living plan, but deviations should preserve the core principles: explicit semantics, local reasoning, and human–machine collaboration.
