# T Language Implementation Snapshot and Human Stress-Testing Guide

This document gives a practical snapshot of what is currently implemented in the repository, and proposes stress-testing scenarios that human testers can execute to evaluate correctness, stability, performance, and ergonomics.

> Scope: this is an implementation-facing checklist based on the current code layout (`src/`, `tests/`, `docs/`) and existing test assets.

---

## 1) What is implemented today

## 1.1 Language core

The repository contains a complete interpreter pipeline:

- **Lexer** (`src/lexer.mll`)
- **Parser** (`src/parser.mly`)
- **AST definitions** (`src/ast.ml`)
- **Evaluator / runtime execution** (`src/eval.ml`)
- **Type-checking layer** (`src/typecheck.ml`)
- **REPL entry point** (`src/repl.ml`)
- **Error system** (`src/error.ml`)

From docs and tests, the core language supports:

- Expressions and function application
- Pipelines (`|>` and `?|>` semantics)
- Formula-style syntax for modeling
- Intent blocks for LLM-readable metadata
- Explicit NA and explicit error handling semantics

## 1.2 DataFrame + Arrow integration

The codebase includes a dedicated Arrow integration layer:

- FFI stubs (`src/ffi/arrow_stubs.c`)
- Arrow wrappers and compute modules:
  - `src/arrow/arrow_bridge.ml`
  - `src/arrow/arrow_ffi.ml`
  - `src/arrow/arrow_table.ml`
  - `src/arrow/arrow_column.ml`
  - `src/arrow/arrow_compute.ml`
  - `src/arrow/arrow_io.ml`
  - `src/arrow/arrow_owl_bridge.ml`

Data ingestion/output and table helpers are implemented in `packages/dataframe`:

- `read_csv`, `write_csv`
- schema/shape inspection (`colnames`, `nrow`, `ncol`)
- table preview (`glimpse`)
- column-name cleaning helpers

## 1.3 Standard library packages

The package folders under `src/packages/` indicate active implementation of:

- **base**: NA, assertion, error utility functions
- **core**: print/help/introspection/string/list/map helpers
- **math**: scalar + ndarray numerical functions (trig/log/exp/pow/reshape/etc.)
- **stats**: descriptive stats + correlation/covariance + linear model (`lm`) + diagnostics helpers
- **colcraft**: dplyr-like verbs (`select`, `filter`, `mutate`, `arrange`, `group_by`, `summarize`, `ungroup`) and window-function helpers
- **pipeline**: dependency extraction and pipeline node execution
- **explain**: explainability-oriented helpers (`explain`, `explain_json`, intent-field extraction)

## 1.4 Package management and docs tooling

Additional implemented subsystems exist beyond the interpreter:

- **Package manager modules** (`src/package_manager/*.ml`) for scaffolding, release/update, doctoring, template generation, and test discovery
- **Documentation tooling** in `src/tdoc/*.ml` for parsing/serializing registry/doc representations

## 1.5 Testing infrastructure already present

The repository includes extensive test suites:

- `tests/base` (errors, NA, recovery)
- `tests/cli`
- `tests/arrow` (integration, Owl bridge, performance)
- `tests/dataframe`
- `tests/colcraft` (verbs + edge cases + window)
- `tests/stats`
- `tests/integration` (including large datasets)
- `tests/package_manager`
- `tests/golden` (R-vs-T output parity workflows and scripts)

A Makefile also defines a full **golden test pipeline** (`make golden`) with data generation, expected output generation, T execution, and comparison.

---

## 2) Human stress-testing plan

Below are stress-testing scenarios designed for humans to run manually (or semi-manually). They are grouped by risk area and can be done incrementally.

## 2.1 Parser and evaluator robustness

### Stress case A: Deeply nested expressions and pipes

- Create scripts with very long pipeline chains (e.g., 100+ transformations).
- Include multiline formatting, mixed named args, and nested function calls.
- Validate:
  - parser stability (no crashes)
  - deterministic output
  - readable error messages when one stage fails

### Stress case B: Error propagation matrix

- Construct scripts that intentionally trigger:
  - type mismatches
  - divide-by-zero
  - invalid column references
  - invalid function arity
- Compare `|>` vs `?|>` behavior to ensure error-short-circuit semantics remain consistent.

### Stress case C: REPL state durability

- Run long REPL sessions (e.g., 1–2 hours): repeated definitions, overwrites, and failures.
- Verify no progressive slowdown or memory blow-up in typical exploratory workflows.

## 2.2 DataFrame and Arrow stress tests

### Stress case D: Wide and tall data

- Test with:
  - **wide** CSVs (1k+ columns)
  - **tall** CSVs (1M+ rows, if machine allows)
- Exercise `read_csv`, `select`, `filter`, `mutate`, `arrange`, `group_by/summarize`, and `write_csv`.
- Validate:
  - operation completion
  - memory behavior
  - schema stability
  - output correctness on sampled rows

### Stress case E: Null/NA-heavy datasets

- Generate datasets with high NA density (50–90% NA in key columns).
- Run statistical functions with and without NA flags/options.
- Validate explicit NA behavior and absence of silent coercions.

### Stress case F: String and locale edge conditions

- Use UTF-8 heavy datasets (accents, emoji, non-Latin scripts).
- Include odd delimiters/quoting in CSV inputs.
- Validate parsing correctness, string function behavior, and round-trip write/read stability.

## 2.3 Colcraft/data-verb semantics

### Stress case G: Verb composition complexity

- Build realistic pipelines with multiple joins/groupings/mutations/window functions.
- Focus on transitions between grouped and ungrouped states.
- Check invariants:
  - row counts where expected
  - sortedness after `arrange`
  - grouping metadata resets after `ungroup`

### Stress case H: Window function edge grids

- For lag/lead/rank/cumulative features:
  - empty groups
  - single-row groups
  - ties
  - NA-containing order columns
- Compare outputs to known references (R/dplyr) where possible.

## 2.4 Stats and modeling stress tests

### Stress case I: Numerical stability checks

- Run `mean/sd/var/cov/cor/quantile` on:
  - very small numbers
  - very large numbers
  - mixed scales
- Validate against R or Python references with tolerances.

### Stress case J: Linear model boundary behavior

- Stress `lm` with:
  - collinearity
  - constant predictors
  - tiny samples
  - NA contamination
- Validate diagnostics and error reporting quality.

## 2.5 Golden/regression stress

### Stress case K: Repeated golden runs

- Execute golden pipeline repeatedly across commits or over time.
- Look for flaky outputs, non-determinism, and formatting drift.
- Keep a simple dashboard: pass/fail by script, runtime trend, and mismatch categories.

## 2.6 Package manager and docs stress

### Stress case L: Lifecycle simulation

- Create several dummy packages with malformed and valid metadata.
- Run scaffold/update/release/doctor/test-discovery flows.
- Validate failure modes are actionable (clear diagnostics, no partial-corrupt states).

---

## 3) Suggested execution order for humans

For practical manual QA, run this order:

1. **Smoke**: parser/runtime + small dataframe ops
2. **Correctness**: golden parity + edge-case semantic checks
3. **Stress**: large datasets, long pipelines, REPL longevity
4. **Numerics**: stats/model tolerance validation
5. **Tooling**: package manager and docs workflows

This ordering finds critical breakages early while still covering long-tail reliability.

---

## 4) Exit criteria for a “good stress cycle”

A stress cycle should be considered successful if:

- No interpreter crashes (only structured errors)
- No silent data corruption observed in sampled or golden-compared outputs
- No major memory leak symptoms in long sessions
- Statistical outputs stay within expected tolerance vs reference implementations
- Tooling failures are diagnosable and recoverable

---

## 5) Notes for maintainers

- Keep adding stress fixtures to `tests/golden/t_scripts` and large-data integration tests.
- When a production-like bug is found manually, convert it into a deterministic regression test immediately.
- Track runtime and memory trends over time for representative stress scripts (not only pass/fail).
