# Phased Roadmap to Version 0.53.0 (Revised: Nix-Native Architecture)

This document outlines the evolution of the T language from **v0.52.0** to **v0.53.0 "L'Initiation"**. This revision focuses on a clean separation of concerns: **T is the authoring and analysis layer**, while **Nix is the execution and caching engine**.

---

## v0.52.1 — Observability & Error Composition 🎯 **OBSERVABILITY**

**Objective**: Make pipeline outcomes queryable as first-class T values and harden existing runtimes.

### Structured Build Logs as First-Class Values
- [x] **`build_log(p)` → `VBuildLog`**: Expose the underlying Nix build results as a T record. Today, these are JSON files; making them first-class values allows programmatic inspection of build health.
  ```t
  log = build_pipeline(p)
  log.nodes             -- List of node records (name, status, duration)
  log.duration          -- Total wall-clock time
  log.failed_nodes      -- Names of nodes that produced VError
  ```
- [x] **`build_log_to_frame(log)`**: Tabulate build results (one row per node) for analysis using `colcraft` verbs.
- [x] **`collect_errors(p)`**: Gather all `VError` artifacts from a built pipeline into a `List`.

### Error Composition Primitives
- [x] **`error_summary(errors)`**: Convert a list of errors into a DataFrame (`node`, `code`, `message`, `runtime`).
- [x] **`error_chain(err1, err2)`**: Explicitly chain multiple errors to preserve provenance when one failure is caused by another.

### Runtime Hardening (Shell & Julia)
- [x] **Shell node maturity**: Implement `capture = "stdout"` sugar for `shn()`. Standardize `T_INPUT_<dep>` environment variables for easier shell script authoring.
- [x] **Julia parity**: Ensure `jln()` has full feature parity with `rn()` and `pyn()` (including PMML/Arrow projection registry).

---

## v0.52.2 — Nix-Native Orchestration 🎯 **ORCHESTRATION**

**Objective**: Align T's pipeline management with Nix's execution model. Avoid re-implementing what Nix already does (parallelism, caching, partial builds).

### Ergonomic Nix Build Wrappers
- [x] **T-to-Nix flag mapping**: Update `build_pipeline()` and `pipeline_run()` to accept parameters that map directly to `nix build` flags:
  - [x] `targets = [...]` → Build specific derivations (`-A`).
  - [x] `force = [...]` → Pass `--check` (force-rebuild).
  - [x] `dry_run = true` → Pass `--dry-run` and return the plan as a DataFrame.
  - [x] `max_jobs = N` → Control Nix parallelism (`--max-jobs`).
- [x] **Cachix Integration**: Add a `cache` parameter to `build_pipeline()` and `pipeline_run()` to automatically configure Nix substituters for binary cache usage (`--option extra-substituters`).

### Multi-Runtime Interchange
- [ ] **Automatic Serializer Negotiation**: (Rejected: Explicit design choice to avoid silent magic. Users define formats explicitly.)
- [x] **Static Format Verification**: The pipeline builder should verify that producer/consumer format types match *before* generating the Nix expression (integrated statically in OCaml builder).

### Future Nix Orchestration Extensions (Brainstorming)
- [x] **Remote Builders Integration (`builders`)**: Support offloading computationally intensive pipeline nodes (e.g. large ML models) to external GPU clusters or high-performance remote builders using standard Nix remote builder configurations (`--builders`).
- [x] **Environment Pass-Through Whitelisting (`keep_env`)**: Explicitly whitelist and forward specific host environment variables (like access tokens or API keys) into the Nix sandbox during developer builds while maintaining strict purity defaults.
- [x] **Advanced Sandboxing Controls (`sandbox`)**: Introduce fine-grained sandboxing options within `nix_options` (e.g., `sandbox: "relaxed" | "strict" | "none"`) mapping directly to Nix isolation policies for legacy or system-dependent workflow steps.
- [x] **Low-level Derivation Projection (`pipeline_to_drv`)**: Provide introspection functions that return the raw Nix store derivation `.drv` paths for each node, enabling developers to perform static analysis and debug Nix inputs at the lowest level.
- [x] **Store Path Introspection (`pipeline_to_store`)**: Provide companion introspection to `pipeline_to_drv` that returns the realised output paths in `/nix/store/` for nodes, evaluated statically via Nix without executing a build.
- [x] **Global Build Configuration (`set_nix_defaults`)**: Introduce a session-wide global defaults configurer `set_nix_defaults(nix_options = [...])` to establish persistent Nix build options (e.g. Cachix caches, max-jobs, sandboxing, builders) across all subsequent pipeline invocations.
- [x] **Cache Status Introspection (`pipeline_cache_status`)**: Introduce `pipeline_cache_status(p)` to query Nix cache validity and presence (`nix-store --query --valid`) on each node's derivation, returning a DataFrame with columns `node` (String), `cached` (Bool), and `store_path` (String) to preview cache hits.

---

## v0.52.3 — Meta-Pipelines & Pipeline Algebra 🎯 **COMPOSITION**

**Objective**: Treat pipelines as composable functions.

### Meta-Pipelines (`pipeline_of`)
- [x] **`pipeline_of` block**: Compose multiple pipelines into a higher-order DAG.
  ```t
  meta = pipeline_of {
    etl   = p_etl,
    stats = p_stats,
    depends = [stats => etl]
  }
  ```
- [x] **`meta_flatten(meta)`**: Transform a meta-pipeline into a single flat pipeline with namespaced nodes (`etl.raw_data`).

### Pipeline Algebra & Templates
- [x] **Parameterization via Lambdas**: Instead of new keywords, promote the use of lambdas returning pipelines: `\(input) pipeline { ... }`.
- [x] **Artifact Export & Import**: Add capabilities to export/import the build cache of a pipeline to enable sharing artifacts between machines (e.g. building on computer A, exporting, importing on computer B, and skipping builds).
  - **REPL functions**: `export_artifacts(p, archive_path)` and `import_artifacts(archive_path)`.

### Future Composition & Cache Extensions (Brainstorming)
- [x] **Meta-Pipeline Visualisation**: Add `pipeline_to_dot(p)` or `pipeline_to_mermaid(p)` to generate graph visualizations for understanding complex, flattened meta-pipelines.
- [x] **Mermaid Browser Visualization**: Enhance `show_plot()` to support detecting Mermaid syntax strings, Pipelines, or Meta-Pipelines, dynamically rendering them to a temporary HTML page with the Mermaid JS client, and opening them in the browser.
- [x] **Granular Artifact Export**: Support exporting specific sub-pipelines or individual nodes (e.g., `export_artifacts(meta.stats, path)`).
- [x] **Artifact Archive Introspection**: Introduce `inspect_artifacts(path)` to read `.nar` cache metadata and return a DataFrame of included nodes and statistics without unpacking.
- [x] **Cache-Aware Dry Runs**: Enhance `populate_pipeline(p, dry_run = true)` to report which nodes would hit the cache and which would actually rebuild based on local or remote substitutes.
- [x] **Execution Plan Serialization**: Allow `dry_run = true` to return a structured DataFrame with columns `node`, `action` (`rebuild` | `fetch` | `cache_hit`), and `store_path` to enable programmatic execution plan analysis and abort thresholds.
- [x] **Programmatic Garbage Collection**: Add a `pipeline_gc(p)` or `t_gc()` function to safely clean up old, detached derivations directly from the T-Lang REPL.

---

## v0.53.0 — "L'Initiation" — The Platform 🚀 **MILESTONE**

**Objective**: Deliver T as a complete, Nix-native platform for polyglot DAG orchestration.

### Unified Diagnostics & Reporting
- [ ] **`pipeline_report(p)`**: Generate a comprehensive `VReport` value.
- [ ] **`render_report(report, format = "html")`**: Static HTML report with an embedded SVG DAG visualization (using Graphviz via Nix).
- [ ] **Cross-Runtime Structured Logging**: Implement a shared JSON logging protocol for all runtimes, queryable in T via `read_node(..., which_log = "structured")`.

### CI/CD Integration
- [x] **`pipeline_ci(p)`**: Generate a standalone, T-free Nix flake that can build the entire pipeline in any Nix-enabled CI (GitHub Actions, etc.).
- [x] **GitHub Actions Helper**: Official action for running T pipelines with Nix + Cachix support.

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
