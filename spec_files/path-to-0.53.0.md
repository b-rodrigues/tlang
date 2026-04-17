# Phased Roadmap to Version 0.53.0

This document outlines the step-by-step evolution of the T language from the **v0.52.0 "Kaméhaméha"** milestone through several targeted point releases, culminating in the **v0.53.0 "Hōkūle'a"** release — a full-fledged polyglot DAG orchestration platform with composable error handling, meta-pipelines, and deep Nix integration.

All features described here assume that v0.52.0 (Julia first-class support, `jn()` node constructor, zero-copy Arrow interchange for Julia, and final stabilization) has shipped.

---

## v0.52.1 — Shell & Julia Hardening + Structured Build Logs 🎯 **OBSERVABILITY**

**Objective**: Harden the two newest runtimes (shell and Julia), and make pipeline build outcomes fully queryable as first-class T values.

### Shell Node Maturity

- [ ] **Exec mode vs. shell mode enforcement**: Validate at pipeline-build time that `command` + `args` (exec mode) and `command` + `shell` (shell mode) are mutually exclusive. Emit a clear `ValueError` if both are specified.
- [ ] **Environment variable contract**: Standardize `T_INPUT_<dep>`, `T_OUTPUT`, and `T_OUTPUT_DIR` environment variables for all shell nodes. Document the contract in `docs/shell-nodes.md`.
- [ ] **stdin/stdout capture mode**: Add `capture = "stdout"` option to `shn()` that treats the process stdout as the artifact (instead of requiring a write to `T_OUTPUT`). This is opt-in sugar for `awk`/`jq`-style one-liners.
- [ ] **Exit code propagation**: Non-zero exit codes become `VError` artifacts with `code = "ProcessError"` and `context.exit_code`. stderr is captured in `context.stderr`.

### Julia Node Hardening

- [ ] **`jn()` parity with `rn()` and `pyn()`**: Ensure `jn()` supports `script =`, `functions =`, `include =`, `serializer =`, `deserializer =`, and `noop =` with identical semantics.
- [ ] **Julia sandbox template**: Ship a Nix template for Julia environments that includes `Arrow.jl`, `DataFrames.jl`, and `GLM.jl` by default. Wire into `tproject.toml` under `[julia-deps]`.
- [ ] **Julia projection registry**: Implement `__type__` / `__version__` JSON projection for `GLM.LinearModel` and `DataFrames.DataFrame` (Arrow IPC path), matching the existing R/Python projection protocol.

### Structured Build Logs as First-Class Values

- [ ] **`build_log(p)` → `VBuildLog`**: Return a structured value from `build_pipeline(p)` containing per-node build status, timings, artifact paths, and diagnostics. Today, build logs are JSON files on disk; expose them as queryable T values.
  ```t
  log = build_pipeline(p)
  log.nodes             -- List of node build results
  log.duration          -- Total wall-clock build time
  log.failed_nodes      -- List[String] of nodes that soft-failed
  log.warnings          -- Aggregated pipeline warnings
  ```
- [ ] **`build_log_to_frame(log)`**: Convert a build log to a DataFrame for tabular inspection (one row per node, columns: `name`, `runtime`, `status`, `duration_s`, `artifact_path`, `n_warnings`, `error_message`).
- [ ] **`compare_builds(log1, log2)`**: Diff two build logs to see what changed between runs (new nodes, removed nodes, status changes, timing deltas). Useful for CI regression detection.

### Error Composition Primitives

- [ ] **`collect_errors(p)` → `List[VError]`**: Gather all `VError` artifacts from a built pipeline into a single list for batch inspection.
- [ ] **`error_summary(errors)` → `DataFrame`**: Tabulate a list of errors into a DataFrame with columns `node`, `code`, `message`, `runtime`, `has_traceback`.
- [ ] **`error_chain(err1, err2, ...)` → `VError`**: Compose multiple errors into a single chained error with full provenance. The resulting error's `context.chain` field contains the ordered list of constituent errors.

---

## v0.52.2 — Polyglot DAG Execution Engine 🎯 **ORCHESTRATION**

**Objective**: Enable true multi-runtime DAG pipelines where R, Python, Julia, shell, and T nodes freely interoperate with automatic data interchange.

### Automatic Serializer Negotiation

- [ ] **Inter-node format inference**: When two connected nodes use different runtimes, the pipeline builder should automatically select the optimal interchange format:
  - T ↔ R: Arrow IPC
  - T ↔ Python: Arrow IPC
  - T ↔ Julia: Arrow IPC
  - R ↔ Python (via T): Arrow IPC (two-hop through the Nix store)
  - Any ↔ Shell: `text` / `json` / `arrow` based on the declared deserializer
  - Model interchange: PMML or ONNX based on the serializer annotation
- [ ] **Serializer compatibility matrix**: Implement a static check in the pipeline builder that validates all edges in the DAG have compatible serializer/deserializer pairs. Emit a clear table of mismatches on failure.
- [ ] **`^parquet` serializer**: Add Parquet as a built-in serializer option for large tabular datasets where Arrow IPC is too ephemeral (e.g., long-lived caches).

### DAG-Level Execution Control

- [ ] **`pipeline_run(p, targets = [...])` — Partial execution**: Allow running only a subset of nodes (and their transitive dependencies). This is the T equivalent of `make target`.
  ```t
  pipeline_run(p, targets = ["report", "model_r"])
  ```
- [ ] **`pipeline_run(p, skip = [...])` — Skip nodes**: Inverse of `targets`; run everything except the specified nodes and their exclusive downstream dependents.
- [ ] **`pipeline_run(p, force = [...])` — Force rebuild**: Force specific nodes to rebuild even if their Nix store artifacts are cached.
- [ ] **`pipeline_run(p, dry_run = true)` — Dry-run mode**: Print the execution plan (which nodes would be built, in what order) without actually building anything. Returns a DataFrame of the plan.
- [ ] **Parallel Nix builds**: When the DAG has independent branches, emit Nix derivations that can be built in parallel by `nix build`. Today, nodes are built sequentially; this release should enable `--max-jobs` parallelism at the Nix level.

### Runtime Isolation Improvements

- [ ] **Per-node Nix environment overrides**: Allow individual nodes to pin different versions of R/Python/Julia packages, overriding the project-level defaults. This enables gradual migration and A/B testing of library versions.
  ```t
  model_v1 = rn(
    command = <{ lm(mpg ~ wt, data = raw_data) }>,
    env_override = [r_packages: ["MASS@7.3-60"]]
  )
  ```
- [ ] **Sandbox resource limits**: Allow optional `memory_limit` and `timeout` parameters on nodes to prevent runaway computations from consuming the build machine.
  ```t
  heavy_model = pyn(
    script = "train_xgb.py",
    timeout = 3600,
    memory_limit = "8G"
  )
  ```

---

## v0.52.3 — Meta-Pipelines & Pipeline Algebra 🎯 **COMPOSITION**

**Objective**: Enable pipelines-of-pipelines (meta-pipelines) and a rich algebra for composing, templating, and parameterizing pipeline graphs.

### Meta-Pipeline (`pipeline_of`)

- [ ] **`pipeline_of` block**: A new top-level construct that composes multiple pipelines into a higher-order DAG where each "node" is itself a pipeline.
  ```t
  meta = pipeline_of {
    etl       = p_etl,
    modeling   = p_model,
    reporting  = p_report,
    depends    = [
      modeling  => etl,
      reporting => [modeling, etl]
    ]
  }
  ```
- [ ] **`build_meta(meta)`**: Build a meta-pipeline by building each constituent pipeline in dependency order. The output of upstream pipelines is made available to downstream pipelines via the Nix store. Build logs are aggregated across all sub-pipelines.
- [ ] **`meta_status(meta)` → `DataFrame`**: Return a status DataFrame with one row per sub-pipeline: `name`, `status`, `n_nodes`, `n_errors`, `n_warnings`, `duration_s`.
- [ ] **`meta_flatten(meta)` → `Pipeline`**: Flatten a meta-pipeline into a single unified pipeline (with automatic `rename_node` to prevent collisions using `<pipeline_name>.<node_name>` prefixes).
- [ ] **Cross-pipeline artifact references**: Within a `pipeline_of` block, downstream pipelines can reference artifacts from upstream pipelines using qualified names:
  ```t
  reporting = pipeline {
    summary_table = read_node("modeling.predictions")
    report = qn(script = "report.qmd")
  }
  ```

### Pipeline Templates & Parameterization

- [ ] **`pipeline_template` construct**: Define a reusable pipeline skeleton with holes (parameters) that are filled at instantiation time.
  ```t
  etl_template = pipeline_template(
    params = [input_path: String, clean_fn: Function],
    body = \(params) pipeline {
      raw  = node(command = read_csv(params.input_path), runtime = T)
      clean = raw |> params.clean_fn()
    }
  )

  etl_prod = instantiate(etl_template, input_path = "data/prod.csv", clean_fn = my_cleaner)
  etl_dev  = instantiate(etl_template, input_path = "data/dev.csv",  clean_fn = my_cleaner)
  ```
- [ ] **`instantiate(template, ...)` → `Pipeline`**: Instantiate a pipeline template with concrete parameter values. Type-checks parameters against the declared schema.
- [ ] **`parameterize(p, param_name, values)` → `List[Pipeline]`**: Generate multiple pipeline instances by varying a single parameter across a list of values. This is the pipeline equivalent of a parameter sweep / grid search.
  ```t
  configs = parameterize(etl_template, "input_path", [
    "data/q1.csv", "data/q2.csv", "data/q3.csv", "data/q4.csv"
  ])
  -- configs is a List of 4 pipelines, one per quarter
  ```

### Pipeline Diffing & Versioning

- [ ] **`pipeline_diff(p1, p2)` → `DataFrame`**: Compute a structural diff between two pipeline versions. Reports added/removed/modified nodes, changed runtimes, changed serializers, and rewired dependencies.
- [ ] **`pipeline_hash(p)` → `String`**: Compute a deterministic content hash of the pipeline's structure (node names, commands, runtimes, dependencies, serializers). Two structurally identical pipelines produce the same hash regardless of definition order. Useful for cache keys and CI fingerprinting.
- [ ] **`pipeline_freeze(p, path)`**: Serialize a pipeline's structural definition to a JSON file for version control. Does not include artifacts — only the graph structure and configuration.
- [ ] **`pipeline_thaw(path)` → `Pipeline`**: Reconstruct a pipeline from a frozen JSON definition. Enables sharing pipeline structures without sharing the Nix store.

---

## v0.53.0 — "Hōkūle'a" — Full Orchestration Platform 🚀 **MILESTONE**

**Objective**: Deliver T as a complete, Nix-native data pipeline orchestration platform with full observability, CI integration, and production-grade polyglot execution.

### Unified Error & Diagnostic System

- [ ] **`pipeline_report(p)` → `VReport`**: Generate a comprehensive pipeline report containing:
  - Build status per node (success / soft-fail / skipped / cached)
  - Per-node timings and resource usage
  - Aggregated warnings with provenance chains
  - Error chains with full tracebacks (R, Python, Julia, shell)
  - Serializer/deserializer format used per edge
  - Nix derivation hashes per node
  ```t
  report = pipeline_report(p)
  report |> filter_node($status == "error") |> select_node($name, $error_message, $traceback)
  ```
- [ ] **`render_report(report, format = "html")`**: Render a pipeline report to HTML, Markdown, or JSON. The HTML report includes a DAG visualization with color-coded node statuses and clickable error details.
- [ ] **Structured logging across runtimes**: All runtimes (R, Python, Julia, shell, T) emit structured JSON log lines during execution. These are captured per-node and queryable via `read_node(name, which_log = "structured")`.
  ```t
  -- In a Python node:
  -- import t_log; t_log.info("Training started", epoch=1, lr=0.01)
  
  logs = read_node("model_py", which_log = "structured")
  -- Returns a DataFrame: timestamp, level, message, epoch, lr, ...
  ```

### CI/CD Integration

- [ ] **`pipeline_ci(p)` → `NixExpression`**: Generate a standalone Nix expression that can build the entire pipeline in a CI environment (GitHub Actions, GitLab CI, etc.) without requiring the T interpreter at build time. The Nix expression encodes the full DAG, all node commands, and all dependency specifications.
- [ ] **`pipeline_cache_key(p)` → `String`**: Compute a cache key for CI based on the pipeline structure hash + input file hashes. Enables incremental CI builds where only changed sub-graphs are rebuilt.
- [ ] **`pipeline_artifacts(p)` → `Dict`**: Return a dictionary mapping node names to their Nix store artifact paths. Useful for CI artifact upload steps.
- [ ] **GitHub Actions helper**: Ship a reusable GitHub Action (`b-rodrigues/t-pipeline-action`) that runs `build_pipeline` in a Nix-enabled runner with Cachix support.

### Conditional & Dynamic Pipelines

- [ ] **`when(condition, node)` — Conditional nodes**: Nodes that are only included in the pipeline when a condition is true. The condition is evaluated at pipeline-construction time (not build time).
  ```t
  p = pipeline {
    raw = node(command = read_csv("data.csv"), runtime = T)
    expensive_model = when(env("FULL_BUILD") == "1",
      pyn(script = "train_deep.py", timeout = 7200)
    )
    report = qn(script = "report.qmd")
  }
  ```
- [ ] **`fork(condition, if_true, if_false)` — Conditional branching**: Choose between two alternative nodes based on a condition. Both branches are validated, but only one is built.
  ```t
  model = fork(
    length(raw |> pull($mpg)) > 1000,
    if_true  = pyn(script = "train_xgb.py"),
    if_false = rn(command = <{ lm(mpg ~ wt, data = raw_data) }>)
  )
  ```
- [ ] **`repeat_until(pipeline, predicate, max_iter = 10)` — Iterative pipelines**: Run a pipeline repeatedly until a predicate on its output is satisfied. Each iteration's artifacts are stored separately in the Nix store. Useful for convergence checks in iterative algorithms.

### Pipeline Observability Dashboard

- [ ] **`pipeline_serve(p, port = 8080)`**: Start a local HTTP server that serves a live dashboard for a built pipeline. The dashboard shows:
  - Interactive DAG visualization (DOT → SVG via Graphviz)
  - Node details on click (runtime, command, timings, logs, artifact preview)
  - Error/warning summary panel
  - Build history timeline (from stored build logs)
- [ ] **WebSocket live updates**: When `pipeline_run` is executing, the dashboard updates in real-time as nodes complete.
- [ ] **`pipeline_dot(p, format = "svg")` — Extended DOT export**: Support SVG and PNG output in addition to raw DOT strings. Use Graphviz (available via Nix) for rendering.

### Advanced DAG Algebra

- [ ] **`map_nodes(p, fn)` — Map over all nodes**: Apply a transformation function to every node in the pipeline. The function receives a node metadata record and returns a modified record.
  ```t
  -- Add a timeout to every Python node
  p_hardened = p |> map_nodes(\(node) {
    if (node.runtime == "Python") node |> set($timeout, 3600)
    else node
  })
  ```
- [ ] **`fold_pipeline(p, init, fn)` — Pipeline fold**: Traverse the DAG in topological order and accumulate a result. Useful for computing aggregate statistics or generating documentation.
  ```t
  total_deps = fold_pipeline(p, 0, \(acc, node) acc + length(node.deps))
  ```
- [ ] **`pipeline_zip(p1, p2, join_on = "name")` — Pipeline zip**: Align two pipelines by node name and produce a pipeline of paired nodes. Useful for A/B comparisons of pipeline variants.

### Nix Integration Deepening

- [ ] **`pipeline_flake(p, path = ".")` — Generate a standalone flake**: Export the entire pipeline as a self-contained Nix flake that can be built without the T interpreter. The flake includes all node derivations, the DAG wiring, and a `default` output that builds everything.
- [ ] **`pipeline_container(p, format = "docker")` — Container export**: Generate a Docker/OCI container image (via Nix's `dockerTools`) that contains the built pipeline artifacts and a minimal runtime. Useful for deploying pipeline results.
- [ ] **Nix remote builders**: Support delegating node builds to remote Nix builders (`--builders` flag). This enables distributing heavy computations (e.g., GPU training) to specialized machines while keeping the DAG coordination local.
- [ ] **Nix binary cache integration**: First-class support for pushing/pulling pipeline artifacts to/from a Nix binary cache (Cachix or self-hosted). Enables team-wide caching of expensive pipeline steps.
  ```t
  build_pipeline(p, cache = "mycachix:my-pipeline-cache")
  ```

---

## Design Principles for 0.52.x → 0.53.0

These principles guide all features proposed above:

1. **Pipelines are data.** Pipelines, build logs, errors, and diagnostics are all first-class T values. They can be inspected, filtered, transformed, and composed using the same functional vocabulary as DataFrames.

2. **Nix is the execution engine.** Every pipeline node is a Nix derivation. Caching, reproducibility, sandboxing, and parallelism come from Nix, not from T. T is the *authoring* layer; Nix is the *execution* layer.

3. **Errors are composable.** Errors are values that can be collected, chained, summarized, and tabulated. A failed pipeline is not an opaque crash — it is a queryable data structure.

4. **Polyglot by design.** R, Python, Julia, shell, Quarto, and T nodes are interchangeable from the pipeline's perspective. The serialization boundary is the only thing that changes between runtimes.

5. **Meta-pipelines are the natural next step.** Once individual pipelines are stable, composing them into larger workflows (ETL → Modeling → Reporting) should be as natural as composing functions.

6. **No implicit behavior.** Every default is explicit. Every fallback is documented. Every error is structured. Transparency wins over convenience.

7. **CI is a first-class target.** Pipelines should be as easy to run in CI as locally. The Nix-native design makes this possible; T should provide the ergonomic wrappers.

---

## Summary

| Version | Codename | Theme | Key Deliverables |
|---------|----------|-------|------------------|
| 0.52.1 | — | Observability | Shell/Julia hardening, structured build logs, error composition primitives |
| 0.52.2 | — | Orchestration | Automatic serializer negotiation, partial/parallel DAG execution, per-node isolation |
| 0.52.3 | — | Composition | Meta-pipelines, pipeline templates, parameterization, diffing/versioning |
| 0.53.0 | Hōkūle'a | Platform | Unified diagnostics, CI/CD integration, conditional pipelines, dashboard, Nix deepening |

Each release builds on the previous one. The progression is:

```
0.52.1: Make polyglot nodes robust and errors queryable
  ↓
0.52.2: Make the DAG execution engine smart and flexible
  ↓
0.52.3: Make pipelines composable and reusable at scale
  ↓
0.53.0: Make T a production-grade orchestration platform
```
