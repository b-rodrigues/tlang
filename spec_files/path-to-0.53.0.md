# Phased Roadmap to Version 0.53.0 (Revised: Nix-Native Architecture)

This document outlines the evolution of the T language from **v0.52.0** to **v0.53.0 "L'Initiation"**. This revision focuses on a clean separation of concerns: **T is the authoring and analysis layer**, while **Nix is the execution and caching engine**.

---

## v0.52.1 — Observability & Error Composition 🎯 **OBSERVABILITY**

**Objective**: Make pipeline outcomes queryable as first-class T values and harden existing runtimes.

### Structured Build Logs as First-Class Values
- [ ] **`build_log(p)` → `VBuildLog`**: Expose the underlying Nix build results as a T record. Today, these are JSON files; making them first-class values allows programmatic inspection of build health.
  ```t
  log = build_pipeline(p)
  log.nodes             -- List of node records (name, status, duration)
  log.duration          -- Total wall-clock time
  log.failed_nodes      -- Names of nodes that produced VError
  ```
- [ ] **`build_log_to_frame(log)`**: Tabulate build results (one row per node) for analysis using `colcraft` verbs.
- [ ] **`collect_errors(p)`**: Gather all `VError` artifacts from a built pipeline into a `List`.

### Error Composition Primitives
- [ ] **`error_summary(errors)`**: Convert a list of errors into a DataFrame (`node`, `code`, `message`, `runtime`).
- [ ] **`error_chain(err1, err2)`**: Explicitly chain multiple errors to preserve provenance when one failure is caused by another.

### Runtime Hardening (Shell & Julia)
- [ ] **Shell node maturity**: Implement `capture = "stdout"` sugar for `shn()`. Standardize `T_INPUT_<dep>` environment variables for easier shell script authoring.
- [ ] **Julia parity**: Ensure `jn()` has full feature parity with `rn()` and `pyn()` (including PMML/Arrow projection registry).

---

## v0.52.2 — Nix-Native Orchestration 🎯 **ORCHESTRATION**

**Objective**: Align T's pipeline management with Nix's execution model. Avoid re-implementing what Nix already does (parallelism, caching, partial builds).

### Ergonomic Nix Build Wrappers
- [ ] **T-to-Nix flag mapping**: Update `build_pipeline()` and `pipeline_run()` to accept parameters that map directly to `nix build` flags:
  - `targets = [...]` → Build specific derivations.
  - `force = [...]` → Pass `--rebuild`.
  - `dry_run = true` → Pass `--dry-run` and return the plan as a DataFrame.
  - `max_jobs = N` → Control Nix parallelism.
- [ ] **Cachix Integration**: Add a `cache` parameter to `build_pipeline()` to automatically configure Nix substituters for binary cache usage.

### Multi-Runtime Interchange
- [ ] **Automatic Serializer Negotiation**: Implement a compatibility matrix. When `rn()` connects to `pyn()`, T should automatically default to `^arrow` interchange unless overridden.
- [ ] **Static Format Verification**: The pipeline builder should verify that producer/consumer format types match *before* generating the Nix expression.

### Runtime Isolation
- [ ] **Per-node Env Overrides**: Allow nodes to specify local package versions (e.g., `env_override = [r_packages: ["MASS@7.3-60"]]`) which T translates into unique Nix derivation environments.

---

## v0.52.3 — Meta-Pipelines & Pipeline Algebra 🎯 **COMPOSITION**

**Objective**: Treat pipelines as composable functions.

### Meta-Pipelines (`pipeline_of`)
- [ ] **`pipeline_of` block**: Compose multiple pipelines into a higher-order DAG.
  ```t
  meta = pipeline_of {
    etl   = p_etl,
    stats = p_stats,
    depends = [stats => etl]
  }
  ```
- [ ] **`meta_flatten(meta)`**: Transform a meta-pipeline into a single flat pipeline with namespaced nodes (`etl.raw_data`).

### Pipeline Algebra & Templates
- [ ] **Parameterization via Lambdas**: Instead of new keywords, promote the use of lambdas returning pipelines: `\(input) pipeline { ... }`.
- [ ] **`pipeline_diff(p1, p2)`**: Tabular comparison of two pipeline structures (added/removed nodes, changed dependencies).
- [ ] **`pipeline_hash(p)`**: Deterministic content hash of a pipeline's static structure for use in CI/CD cache keys.

---

## v0.53.0 — "L'Initiation" — The Platform 🚀 **MILESTONE**

**Objective**: Deliver T as a complete, Nix-native platform for polyglot DAG orchestration.

### Unified Diagnostics & Reporting
- [ ] **`pipeline_report(p)`**: Generate a comprehensive `VReport` value.
- [ ] **`render_report(report, format = "html")`**: Static HTML report with an embedded SVG DAG visualization (using Graphviz via Nix).
- [ ] **Cross-Runtime Structured Logging**: Implement a shared JSON logging protocol for all runtimes, queryable in T via `read_node(..., which_log = "structured")`.

### CI/CD Integration
- [ ] **`pipeline_ci(p)`**: Generate a standalone, T-free Nix flake that can build the entire pipeline in any Nix-enabled CI (GitHub Actions, etc.).
- [ ] **GitHub Actions Helper**: Official action for running T pipelines with Nix + Cachix support.

### Static Conditionals
- [ ] **Static `when()` and `fork()`**: Conditional node inclusion where the condition is evaluated at *pipeline construction time* (preserving Nix's static DAG requirement).
  ```t
  -- This condition is checked when the pipeline is defined, not during build.
  p = pipeline {
    heavy_model = when(env("CI") == "1", pyn(script = "train.py"))
    report = qn(script = "report.qmd")
  }
  ```

### Observability Dashboard
- [ ] **`pipeline_serve(p)`**: A local dashboard that reads Nix store artifacts and build logs to provide an interactive view of the pipeline's current state and history.

---

## Non-Goals & Architectural Boundaries

1. **No Runtime Feedback Loops**: Iterative pipelines (like `repeat_until`) that depend on build-time outputs to modify the DAG are **out of scope**. These conflict with Nix's static derivation model.
2. **No T-managed Execution**: T will never manage its own process pool or thread scheduler for node execution; it will always delegate to `nix build`.
3. **No Dynamic Rewiring**: The DAG structure must be fully determined before the build starts. Any "dynamic" behavior must be handled via static generation in T.
