# Changelog

## [0.53.3] - 2026-06-26

### Toolchain & CI Updates

- **Nixpkgs Snapshot & Package Updates**: Updated the `rstats-on-nix/nixpkgs` snapshot date in `RSTATS-NIX-DATE` to `2026-06-22` along with the corresponding hash updates in `flake.nix`. Added fixes to the `rstats-on-nix/nixpkgs` fork to permanently disable checks for `django` and `twisted` directly in their derivations (preventing build failures on `aarch64-darwin`), which allowed the local overrides in `flake.nix` to be cleaned up.
- **Quarto Patch & Compatibility**: Integrated the Quarto patch (fixing pandoc compatibility and syntax-highlighting replacement issues) directly into the upstream `rstats-on-nix/nixpkgs` fork, allowing the local `postPatch` overrides in `flake.nix` to be simplified.
- **CI Enhancements**: Added `.github/workflows/test-build.yml` for manual matrix builds and adopted the `wimpysworld/nothing-but-nix` GitHub Action to optimize disk space usage during CI runs.

### Reproducible Random Sampling

- **`set_seed(seed)`**: Initialize the global RNG for reproducible random draws.
- **`sample(x, n = 1, replace = false)`**: Randomly sample elements from a Vector or List, with or without replacement.
- **`slice_sample(data, n = 1, replace = false)`**: Randomly sample rows from a DataFrame, with or without replacement.
- All three functions share a common global RNG state; `set_seed()` guarantees identical output across runs.

### Quantile Functions (Inverse CDFs)

- **`qnorm(p, mean = 0, sd = 1)`**: Normal distribution quantile (inverse CDF), using Acklam's algorithm.
- **`qt(p, df)`**: Student t distribution quantile, via binary search on `pt`.
- **`qf(p, df1, df2)`**: F distribution quantile, via binary search on `pf`.
- **`qchisq(p, df)`**: Chi-squared distribution quantile, via binary search on `pchisq`.
- Enables power analysis and exact p-value thresholds natively in T without calling R.

## [0.53.2] - 2026-06-24

### Hotfix

- **Nix Flake Update / Maven Dependency Parity**: Fixed local build failures caused by an upstream change in Maven dependencies for the `jpmml-evaluator` library (used for PMML model scoring). The nixpkgs fetch source hash has been updated to restore local build compatibility.

## [0.53.1] - 2026-06-24
 
### Hotfix

Fix for https://github.com/b-rodrigues/tlang/issues/434

jpmm-statsmodels PR is not yet merged into NixOS/nixpkgs master branch, so it's included
in the rstats-on-nix fork. It seems like the Maven dependencies got cahnged after release
so compilation was failing. This also means that previous releases of T are likely not
installable anymore.

### Timezone Support
- **IANA timezone offset conversion**: `with_tz()` and `force_tz()` now correctly
  apply timezone offsets via POSIX `localtime_r`, supporting full IANA timezone
  names (e.g. `"Europe/Paris"`, `"America/New_York"`).

### Arrow Native Path Improvements
- **Preserve factor type for all-NA columns**: `to_factor` on all-NA input now
  preserves factor metadata (levels, ordered) through the Arrow round-trip,
  keeping the native Arrow path active across data cleaning pipelines.
- **Preserve column type for all-NA columns**: typed `VNA` variants (`NAInt`,
  `NAFloat`, `NADate`, `NADatetime`, …) now set the corresponding type flag in
  `values_to_column`, so all-NA columns route to the correct typed Arrow column
  (e.g. `IntColumn`, `FloatColumn`) instead of always falling back to `NAColumn`.
  Added `NADatetime` variant to disambiguate datetime NAs from date NAs.
- **Typed NA for lag/lead padding**: `lag` and `lead` now inspect the input
  vector's element type and use the appropriate typed NA variant for fill
  positions (e.g. `NA(Int)` for integer vectors, `NA(Float)` for float vectors).
- **Typed NA for outer join unmatched rows**: Left/full joins now produce
  type-correct NA values for unmatched columns, inferred from the source
  Arrow column types. Also fixes empty-group key columns in `group_by` +
  `summarize` and typed NA for Date/Datetime null cells in `pivot_wider`
  and `expand`.

### Core Language Features & Fixes
- **`get()` data-mask awareness**: `get("name")` inside NSE data verbs
  (`mutate`, `filter`, `summarize`, …) now checks the data mask before the
  global environment, enabling dynamic column name resolution.

## [0.53.0] - 2026-06-22

This release:

- **Atelier TUI IDE Integration**: This release introduces full support for the Atelier tmux-based TUI IDE. `t init --project` and `t init --package` now accept `--include-atelier` (CLI flag) to configure the IDE in the project environment. When running inside an active Atelier session, the REPL automatically updates variables, writes diagrams/plots to the `_atelier/` directory, and runs a protected variables watcher via the new `tui_update` builtin. Atelier can also be declared as a project dependency via `[additional-tools]` in `tproject.toml`.
- Introduces static conditionals for pipelines: `node_when(condition, node_value)` and `node_fork(...)` allow conditional node inclusion evaluated at pipeline construction time, preserving Nix's static DAG requirement.
- **VDataFrame JSON serialization**: NAColumn entries are now omitted from JSON output (field absent) rather than serialized as null, so downstream readers see no key rather than an NA/null value.

### Dynamic Branching & Pattern Expansion
- **Pattern-based Branching**: Pipelines can now dynamically expand a single node into multiple branch nodes using pattern functions:
  - `map_pattern(dependency)`: Maps a node over each element of a List, Vector, or DataFrame dependency.
  - `cross_pattern(sub_pattern1, sub_pattern2, ...)`: Generates a Cartesian product of multiple `map_pattern` sub-patterns.
  - `slice_pattern(dependency, indices)`: Creates branches selecting specific element indices.
  - `head_pattern(dependency, n)` / `tail_pattern(dependency, n)`: Restricts branches to the first or last `n` elements.
  - `sample_pattern(dependency, n)`: Randomly samples `n` elements from a dependency (with deterministic seed behavior).
- **`expand_pipeline`**: Adds the built-in function `expand_pipeline(p)` to manually expand dynamic patterns into separate `<node>_branch_<N>` nodes.
- **Auto-Expansion & Guardrails**: Branch expansion is performed automatically before pipeline compilation in `build_pipeline()` and `populate_pipeline()`. Attempting to build/populate a pipeline containing unexpanded patterns raises a compile-time `StructuralError`.
- **Lazy Branch Expansion**: Implemented lazy branch expansion for chained or computed dependencies with patterns, resolving branch dependencies across complex DAGs.
- **Branch Naming & Verification**: Node names containing the suffix `_branch_N` are strictly forbidden in manual definitions to prevent namespace clashes. Duplicate node detection and branch-aware `read_node` errors assist in identifying naming conflicts.

### GitHub Actions Integration
- **`pipeline_to_ga`**: Adds `pipeline_to_ga(p, ...)` to generate a complete GitHub Actions CI workflow YAML. The generated workflow automates Nix-based pipeline runs on push/PR events.
- **Nix Caching in CI**: Integrates with Cachix (defaulting to the `rstats-on-nix` cache) and automatically manages the caching of built Nix artifacts using a repository's `t-runs` branch (archived as `.nar` files).
- **Optional File Output**: Accepts an optional `file` parameter to write the workflow YAML directly to `.github/workflows/<name>.yml` (defaulting to auto-detected project names).

### Pipeline Execution Reporting
- **`pipeline_report`**: Introduces `pipeline_report(p, ...)` to generate structured Markdown (`target = "ssh"`) or HTML (`target = "web"`) execution reports.
- **Detailed Run Metrics**: Reports include built/unbuilt/errored node statuses, depth indicators, runtimes, warning summaries, Mermaid dependency graph visualization, and truncated build error tracebacks.
- **Log Targeting**: Supports the `which_log` regex parameter to report on historical run records.

### Core Language Features & Fixes
- **`float_seq`**: Adds the `float_seq(start, end, n)` built-in function to generate a List of `n` evenly-spaced floats.
- **Assignment Error Propagation**: Blocks (`{ ... }`) no longer silently swallow errors occurring inside assignment/reassignment statements. The error is bound to the variable and propagated correctly, enabling robust recovery patterns via subsequent `match` blocks.

## [0.52.3] - 2026-06-12

This release:

- introduces a new meta-pipeline composition feature (`pipeline_of`), first-class artifact export/import capabilities, meta-pipeline graph visualization, interactive Mermaid browser rendering, and cache-aware dry runs with programmatic garbage collection.
- Introduces lazy pipeline evaluation, deferring T node evaluation to build time and eliminating redundant re-evaluation cycles.
- Includes comprehensive bug fixes across stats, core, CSV, and pipeline subsystems, and a systematic codebase-wide safety refactoring following OCaml best practices.

### Pipeline Soft-Fail & Error Recovery
- **Block Evaluation Error Recovery**: Blocks (`{ ... }`) now abort immediately on encountering a `VError` from a bare expression, preventing silent error accumulation. However, `VError` values from `Assignment` and `Reassignment` statements no longer abort the block — the error is bound to the variable and subsequent statements (typically a `match`) can handle it. This enables patterns like `{ x = 42 / 0; match(x) { Error { msg } => 0, default => x } }` where a risky computation is captured and recovered.
- **Conditional Serialization on soft-fail**: Nodes that soft-fail and return `VError` now conditionally fall back to binary `serialize`/`deserialize` rather than triggering configured custom serializers (like Arrow), preventing crashes.
- **Failed Node Diagnostics**: Host tools and logs now safely resolve and deserialize binary T error payloads.

### Lazy Pipeline Evaluation
- **Deferred T node evaluation**: T nodes are now evaluated lazily — the `get_pipeline_member` function no longer eagerly evaluates T expressions when a pipeline is accessed. Evaluation is deferred to `rerun_pipeline` at build time via `build_pipeline()`. This eliminates redundant re-evaluation cycles, improves performance for large pipelines, and avoids side-effect leakage from unbuilt nodes.
- **Cross-pipeline dependency resolution**: Dependency detection now uses `p.p_nodes` instead of `p.p_exprs` for identifying resolved nodes from other pipelines, improving accuracy of dependency inference.

### Warning Propagation & Diagnostics
- **Upstream warning inheritance**: After `build_pipeline(p)`, downstream nodes now automatically inherit warnings from ancestor nodes. `warning_msg(downstream)` shows warnings with source provenance (`"Ancestor node '<name>' reported following warning: <message>"`). Multiple warnings (own + upstream, or from multiple ancestors) are joined with `". Furthermore, "`.
- **`inspect_node` now shows warnings**: `inspect_node(node)` returns a `warnings` field with a structured list of dicts (`source` + `message`), showing both own and inherited upstream warnings.
- **Removed `.warnings` from `read_node()` return**: The `.warnings` field on `read_node()` results has been removed. Use `warning_msg(node)` for a formatted warning message or `inspect_node(node).warnings` for structured warning metadata.

### Historical Node Access & Build Log Identity
- **`read_past_node(p.node_name, which_log)`**: New NSE-captured function to read a pipeline node from a specific historical build log without the pipeline being in scope. The first argument is captured before evaluation, so `read_past_node(base_p.raw, which_log = "qcfs")` works even when `base_p` is not defined. `which_log` is mandatory — no default.
- **Simplified `read_node`**: The `which_log` parameter has been removed from `read_node`. Use `read_past_node(p.node_name, which_log = "...")` for historical reads, and `read_node(p.node_name)` for in-scope pipeline reads.
- **`pipeline_name` on `build_pipeline`**: `build_pipeline(p, pipeline_name = "my_name")` now records the pipeline name in the build log JSON (`"pipeline"` field). `list_logs()` shows a new `pipeline` column for disambiguation.
- **Removed `pipeline_summary` and `pipeline_dot`**: These convenience aliases have been removed. Use `pipeline_to_frame(p)` instead of `pipeline_summary(p)`, and `pipeline_to_dot(p)` instead of `pipeline_dot(p)`. `pipeline_to_dot` also handles `MetaPipeline`.

### Pipeline Visualization
- **`pipeline_to_dot(p, title = na())`**: Generates a Graphviz DOT representation of the given pipeline or meta-pipeline. New optional `title` parameter auto-detects the project name from `tproject.toml` (fallback: none). Renders as `label=` in the `digraph` header.
- **`pipeline_to_mermaid(p, title = na(), flatten = false)`**: Generates a Mermaid flowchart diagram string from the pipeline topology. New optional `title` parameter auto-detects from `tproject.toml`; new `flatten` parameter (default `false`) renders meta-pipelines as grouped subgraph blocks — set to `true` for flat output.
- **Subgraph rendering as default**: Meta-pipeline sub-pipelines now render as grouped subgraph blocks by default in both Mermaid and DOT output.
- **YAML frontmatter for Mermaid title**: Graph titles are emitted as Mermaid YAML frontmatter (`---\ntlang-title: ...\n---`), visible in the HTML `<h1>` via `show_plot()` but silently ignored by Mermaid.js to avoid in-diagram title duplication.
- **Default T runtime node colour**: Changed from `#ffced0` to `#859900` (green) for a cleaner visual appearance in generated graphs.
- **Browser Visualization via `show_plot`**: `show_plot(p)` now accepts a pipeline or meta-pipeline directly — it calls `pipeline_to_mermaid` internally, renders the DAG as an interactive HTML page, and opens it in the browser. `show_plot(mermaid_string)` also renders arbitrary Mermaid diagram strings.

### Diagnostics & Error Messages
- **`read_node` "Did you mean" hint**: When `read_node` receives a bare symbol (e.g. `read_node(ha)` instead of `read_node(p.ha)`), the error now suggests the correct form: *Did you mean `read_node(p.ha)`?*
- **Unified `read_node` error messages**: All non-`ComputedNode` argument errors now follow a consistent format guiding the user to build the pipeline first, use dot access, or use `read_past_node` for historical builds.

### Artifact Cache, Dry Runs, and Garbage Collection
- **Granular `export_artifacts`**: Support exporting cached Nix artifacts for individual nodes, sub-pipelines, meta-pipelines, or lists/dictionaries of nodes/pipelines.
- **Variadic `import_artifacts`**: Support both 1-argument `import_artifacts(archive_path)` (direct Nix store import) and 2-argument `import_artifacts(target_val, archive_path)` (import and verify paths) calling signatures.
- **`inspect_artifacts(archive_path)`**: Import archive into a temporary, isolated Nix store and return a DataFrame containing the included nodes, store paths, hashes, sizes in bytes, and reference basenames without affecting the local store.
- **Verification & REPL Stability**: Fixed path resolution and correctness checks, and updated package registrations in the interactive REPL for `import_artifacts`, `export_artifacts`, and `inspect_artifacts`.
- **Cache-Aware Dry Runs**: `populate_pipeline(p, dry_run = true)` and `build_pipeline(p, dry_run = true)` now perform a dry run via Nix (`--dry-run`), parsing the plan to report which nodes will hit the local cache (`"cached"`), rebuild (`"build"`), or fetch from remote substituters (`"fetch"`), returning the results as a DataFrame.
- **Programmatic Garbage Collection**:
  - `pipeline_gc(p, dry_run = true)`: Deletes the store paths of the given pipeline `p` if safe. By default (`dry_run = true`), it returns a DataFrame previewing the nodes, store paths, and deletion eligibility status. Set `dry_run = false` to execute the deletion.
  - `t_gc()`: Triggers a global Nix garbage collection (`nix-store --gc`) directly from the REPL to safely clean up old, detached derivations.


### Meta-Pipeline Composition
- **`pipeline_of` block**: A new combinator that composes multiple pipelines into a higher-order DAG. It allows you to define relationships between sub-pipelines in a declarative way, enabling complex, multi-stage workflows.
- **Automatic Dependency Inference**: T-Lang automatically analyzes cross-pipeline references (e.g., referencing `etl.clean` in the `stats` pipeline) to infer the execution order between sub-pipelines. No manual `depends` configuration is required for the flattening engine.
- **Automatic Flattening**: The `meta_flatten` combinator automatically flattens meta-pipelines at execution time. When a meta-pipeline is populated, queried, or inspected, T-Lang automatically flattens it internally. This flattening is done on-demand, so you don't need to manually flatten meta-pipelines.
- **Automatic Namespacing**: Node names are automatically namespaced (e.g., `etl.raw`, `etl.clean`, `stats.summary`) to prevent namespace collisions, and all internal variable references are rewritten accordingly.
- **Cross-Pipeline Reference Rewriting**: Internal references to sub-pipeline nodes (e.g., `p_etl.raw`) are automatically rewritten to their namespaced equivalents (e.g., `etl.raw`) during the flattening process.

### Pipeline Parameterization (Templates)
- **Parameterization via Lambdas**: Standard lambdas returning `pipeline` blocks (e.g., `\(multiplier) pipeline { ... }`) are now fully supported. Outer variables referenced inside the pipeline nodes are automatically substituted with their concrete values during compilation, producing fully independent and Nix-reproducible pipelines.

### Examples

#### Basic Usage
```t
# Define multiple pipelines
p_etl = pipeline { ... }
p_stats = pipeline { ... }

# Compose into a meta-pipeline
meta = pipeline_of {
  etl = p_etl
  stats = p_stats
}

# Built-in commands automatically handle meta-pipelines
populate_pipeline(meta, build = true)
read_node(meta.stats.summary)
inspect_pipeline(meta)
```

#### Graph-Structured Pipeline
```t
meta_graph = pipeline_of {
  raw = pipeline {
    src = read_csv("raw.csv")
  }

  cleaned_a = pipeline {
    a = clean(raw.src)
  }

  cleaned_b = pipeline {
    b = clean(raw.src)
  }

  summary = pipeline {
    val = summarize(cleaned_a.a, cleaned_b.b)
  }
}

# T-Lang automatically infers the execution order:
# raw -> {cleaned_a, cleaned_b} -> summary
populate_pipeline(meta_graph, build = true)
```

### Notes
- The `meta_flatten` combinator is not exposed as a first-class function in the CLI or T-Lang AST. It is an internal implementation detail of the pipeline engine that is automatically invoked when working with `pipeline_of`.

### Bug Fixes

- **Stats — fivenum alignment with R**: Replaced the defective gammp series computation with a correct implementation and adopted Tukey hinges for `fivenum`, ensuring parity with R's `fivenum()` output.
- **Stats — high-precision t-quantile**: Replaced the Cornish-Fisher approximation with exact OCaml root-finding on the pt CDF via `Float.erfc`, improving tail accuracy.
- **Stats — recursive t_quantile**: Made `t_quantile` recursive to handle edge cases in quantile computations correctly.
- **Stats — ss_res in leave-one-out sigma**: Corrected the `ss_res` formula used in `leave_one_out_sigma` calculation in `lm.ml`.
- **Stats — cut formatting**: Changed `cut` to output spaces-free labels formatted with `%g` format, matching R's `cut()` label style.
- **Stats/Core — float/int equality & pnorm accuracy**: Treated float and int values as identical when numerically equal (`3.0 == 3`) and improved `pnorm` accuracy using `Float.erfc`.
- **Core — VFactor/VString equality**: Extended the evaluator to support direct equality comparison between `VFactor` and `VString` values.
- **CSV — empty string NA parsing**: Fixed `read_csv` to parse empty strings as `NA` with `allow-null-strings`, and implemented proper dataframe comparison semantics.
- **Pipeline — JSON float precision**: Configured `jsonlite::write_json` to serialize floats at full precision, preventing rounding-induced mismatches.
- **Pipeline — R JSON NA handling**: Configured the R JSON serializer to write `NA` values as JSON `null` for correct round-tripping.
- **Pipeline — Nix dry-run dot-access quoting**: Correctly quote dot-access attributes (e.g., `node.sub.field`) in Nix dry-run evaluation expressions.
- **Pipeline — mermaid ID collision prevention**: Sanitized node IDs in `pipeline_to_mermaid` to prevent collisions from similar node names.
- **Pipeline — inspect_artifacts resource leaks**: Resolved file descriptor and directory handle leaks in `inspect_artifacts`, and restored scalar `TypeError` for invalid inputs.
- **Pipeline — NixError fallback**: Restored original `NixError` fallback behavior for empty trimmed `last_part` in `builder_internal.ml`.
- **Pipeline — dependency namespace fixes**: Standardized runtime emission helper naming (`__node_result` across all runtimes), fixed R variable naming compatibility (`dep_` prefix), and corrected dependency namespace generation.
- **Pipeline — rename_node cn_name sync**: Fixed a bug where `rename_node` updated the assoc-list key in `p_nodes` but left `VComputedNode.cn_name` unchanged, causing downstream lookups (`resolved_cn`, `computed_node_resolver`, `read_node`) to search using the stale name and fail with `<unbuilt>` path errors.

### Codebase Safety Refactoring

The entire OCaml codebase underwent a systematic safety review following best practices for ML-family languages:

- **Zero partial functions**: Eliminated all uses of `Option.get`, bare `List.hd` on unvalidated lists, and similar partial operations.
- **Exhaustive pattern matching**: Every `match` expression across ~100 files was audited and made total, removing partial wildcard patterns where feasible.
- **No raw exceptions in user paths**: Converted `failwith`, `raise`, and `assert false` in user-facing code to structured `VError` returns.
- **Float comparison hygiene**: Replaced exact float equality with epsilon-aware comparisons and `Float.compare`.
- **Abstract type safety**: Added `.mli` interface files with abstract types for `Arrow`, `GroupedTable`, and key FFI modules.
- **Resource cleanup**: Fixed file descriptor and directory handle leaks in pipeline introspection and inspection code.
- **Code review checklist**: Added an OCaml Code Review Checklist to `AGENTS.md` as a permanent reference for future contributions.


## [0.52.2] - 2026-05-31

This release introduces interactive pipeline node debugging via `debug_node`, native Nix orchestration features for granular rebuild control, job parallelisation, Cachix binary caching, and dry-runs, and the temporal introspection pair `build_log_history` and `node_diff` for tracking how pipeline outputs change across builds.

**Status**: Beta

### Interactive Node Debugging
- **Interactive Node Shells (`debug_node(p.node)`)**: Introduces a new built-in function to drop developers directly from the T REPL into a sandboxed guest REPL (Python, R, or Julia) to step through and debug code using actual upstream outputs.
- **Custom Guest REPL Prompts**: Automatically overrides subshell prompts (`py> `, `r> `, `jl> `) to cleanly signal that you are in a debugger subshell session, returning immediately to the T REPL upon exit.
- **Pristine Debugger Environments**: Keeps the subshell clean by displaying upstream Nix store paths and companion package loading tips on startup rather than polluting the environment with dependency paths.
- **Node Environment Variable Propagation**: Custom environment variables defined inside the node's configuration block (`p_env_vars`) are programmatically inherited by the subshell process.
- **R Quiet Launch Mode**: Suppresses default R welcome copyright and version info blocks on start, providing an instant, clean terminal.
- **Target Runtime Safety Guard**: Restricts interactive debugging sessions strictly to REPL-capable runtimes (Python, R, Julia), raising a descriptive `ValueError` for unsupported runtimes (like Quarto or Bash).
- **Workspace-Wide Package Manager Guards (Nix Shell & Debug REPLs)**: Imperative package manager guards are now enforced globally. In addition to subshells launched via `debug_node()`, running R, Julia, or Python directly inside the development shell started via `nix develop` will automatically intercept and block imperative package mutations (`install.packages()`, `Pkg.add()`, `pip install`, `poetry`, `uv`, `conda`, `python -m pip`, etc.). Running these commands displays a helpful instruction directing developers to declare dependencies in `tproject.toml`, run `t update`, and re-enter `nix develop`, protecting the workspace from drift and preserving reproducible Nix derivation footprints.

### Pipeline Temporal Introspection
- **Pipeline History (`build_log_history(p, n = NA)`)**: Exposes the historical record of builds matching the current pipeline signature as a sorted DataFrame, ordered from most recent to oldest. Uses the 1-indexed `build_rank` convention (where `1` represents the most recent build, `2` the second most recent, etc.).
- **Type-Sensitive Node Diffs (`node_diff(node_a, node_b, log_a = "latest", log_b = "latest")`)**: Compares outputs of a specific node across two historical builds (defaulting to the most recent vs. second most recent). Implements type-sensitive comparison strategies:
  - *DataFrames*: Summarizes schema changes, lists added/removed columns, reports row count shifts, and evaluates column-level mean drift for numeric fields. Note: This highlights high-level summary statistic shifts and does not perform full statistical distribution tests.
  - *PMML Models*: Parses regression coefficients and intercept changes for linear models. For non-linear model formats (e.g. Random Forests, Decision Trees), it falls back to a structural equality diff.
  - *Text Files*: Uses native `diff -u` to extract precise line additions, removals, and diff summaries. Includes a robust fallback if system tools are sandboxed or missing.
  - *Scalars/Generic Fallback*: Direct value structural comparison and numeric delta calculations.

### Serialization & Correctness Fixes
- **Correctness Fix for `"default"`/`"tobj"` Deserialization**: Fixed a major correctness bug in `read_standard_node_value` where scalar nodes serialized with `"default"` or `"tobj"` formats were not being deserialized when queried via standard readers, returning a fallback `VComputedNode` token instead. Standard readers now correctly deserialize value payloads (like `VInt`, `VFloat`) using OCaml's Marshal digestion, enabling precise cross-node value and delta comparisons.

### Nix-Native Orchestration & Rebuild Control
- **Nix Build Flags Integration**: Added full support for `targets`, `force`, `dry_run`, `max_jobs`, and `cache` parameters in `build_pipeline` and `pipeline_run`.
- **Derivation Targets (`targets`)**: Map `targets` to `-A <derivations>` in the underlying `nix build` command, allowing specific parts of the pipeline to be built selectively.
- **Granular Rebuild Control (`force`)**: Map `force` to native `--check` flags. Pass `true` to force-rebuild the entire pipeline, or a string/list of specific node names to force-rebuild only selected steps.
- **Parallel Compilation (`max_jobs`)**: Mapped the `max_jobs` parameter directly to `--max-jobs <N>`, enabling parallel compilation of sandbox environments and derivations.
- **Binary Cache Optimization (`cache`)**: Seamless Cachix binary cache integration by dynamically configuring `extra-substituters` and `extra-trusted-public-keys` (prioritizing `rstats-on-nix` as the preferred default cache).
- **Dry-Run Preview Mode (`dry_run`)**: Implemented a native dry-run mode that parses `nix-build --dry-run` output into a structured T-Lang `DataFrame` (containing columns `node`, `action`, `path`) to inspect build execution plans without mutating local store state.

### Pipeline Propagation & Path Reconciliation
- **Nix Store Path Alignment**: Added a robust post-build step (`update_pipeline_with_build_paths`) that reconciles internal `ComputedNode` paths with the real store paths generated by Nix.
- **Dynamic Argument List Conversion**: Used dynamically parsed array parameters to maintain 100% backward compatibility with previous T-Lang CLI and OCaml process invocations.

### `t doctor` Pipeline Dependency Analysis
- **Static Pipeline Dependency Scanning**: `t doctor` now parses `src/pipeline.t` and statically analyses each node's `command` block to detect runtime packages (`library(...)`, `import ...`, `using ...`) that are referenced but absent from `tproject.toml`. Missing packages are reported as warnings with an actionable suggestion to add them to the relevant `[r-dependencies]`, `[py-dependencies]`, or `[jl-dependencies]` section and run `t update`. All pipeline definitions in the file are scanned, not just the first one.
- **Scoped Warning**: The missing-pipeline-entrypoint warning (no `src/pipeline.t` found) is only emitted when the project has at least one runtime dependency declared, avoiding noise for pure R or Julia package projects.

### API Parity & Testing
- **Robust Builtin Validation**: Added comprehensive type-safety guards for all new orchestration parameters to raise highly readable compile-time warnings and TypeErrors instead of silent Nix failures.
- **High-Coverage Test Harness**: Expanded the unit testing suite in `test_pipeline.ml` to verify dry-run DataFrame output, validation guards, and advanced parameter passthroughs (2271/2271 tests passing).
- **Ecosystem Sync & Docs**: Updated `docs/pipeline_tutorial.md` and `docs/api-reference.md` to formally document the new parameters, along with comparative command mapping tables.

### Multi-Runtime Interchange & Early Safety
- **Populate Pipeline Arity Expansion**: Updated `populate_pipeline()` to support all the new Nix orchestration arguments (`targets`, `force`, `dry_run`, `max_jobs`, `cache`) in the exact same manner as `build_pipeline()`.
- **Early Target & Force Validation**: Integrated compile-time validation of `targets` and `force` node lists in the OCaml pipeline compiler. T-Lang now instantly detects misspelled or nonexistent node targets and raises highly readable `StructuralError` warnings before spawning the Nix interpreter.
- **Node Name Collision Prevention**: Sorted internal name matching patterns by character length in descending order, avoiding potential substring collisions where short node names (e.g. `model`) would erroneously match long node name store paths (e.g. `model_evaluation`).

### Pipeline Temporal Introspection — `node_diff` improvements

- **Line-by-line string diffs**: When comparing string-typed node outputs, `node_diff` now splits the values on newlines and produces a proper unified diff with context lines — the same colourised format already used for text-file nodes. Calling `detailed_summary` on the result shows added/removed lines highlighted in green and red.
- **Reliable `NaN` / `NA` handling in DataFrames**: Cells that contain `NaN` or `NA` on both sides are no longer incorrectly reported as changed.
- **Accurate model change detection**: A model whose coefficients are identical but whose fit statistics (R², AIC, BIC, …) differ is now correctly reported as changed, not identical.
- **Helpful error on missing key column**: If you pass a `key` that does not exist in one of the DataFrames, `node_diff` now raises a clear error immediately instead of silently producing wrong counts.
- **`node_diff` requires `ComputedNode` arguments**: `node_diff` now enforces that both arguments are pipeline node references (e.g. `node_diff(p.my_node, p.my_node)`). Passing a plain string or pipeline object raises a descriptive `TypeError`.

### REPL & `explain()` — Unicode display

- **Unicode characters now render correctly**: String values containing non-ASCII characters (accented letters, symbols like `→`, emoji, …) are displayed as-is in the REPL and inside `explain()` tree output, instead of being shown as raw byte sequences such as `\226\134\146`.

## [0.52.1] - 2026-05-22

This release finalizes end-to-end Julia ONNX serialization support, fixes pipeline compiler strategy dictionary parsing issues, strengthens runtime safety by protecting reserved keywords, and completes the migration of pipeline introspection to a strict, node-centric dot-access model.

**Status**: Beta

### Strict Node-Centric dot-access Migration
- **Strict Node-Centric read_node**: Refactored `read_node()` to strictly require `ComputedNode` arguments (e.g., `read_node(p.node_name)`), disallowing legacy string lookup paths.
- **In-Memory Registry Priority**: Refactored `read_node` OCaml resolution to prioritize the in-memory registry (`Ast.in_memory_node_values`) over disk-based build log artifacts, resolving transient `FileError` omissions when accessing unbuilt or dynamically computed nodes.
- **Dynamic Build Help Messages**: Added dynamic, descriptive walkthroughs upon successful `build_pipeline()` execution, instructing users how to read, inspect, and summarize their pipeline using their actual variables and first-class node objects.
- **Ecosystem-Wide Synchrony**: Migrated the entire `t_demos` workspace and workflows (79+ scripts and workflows) to adopt the new strict dot-access design. Standalone helper scripts are now automatically self-contained with explicit `import 'src/pipeline.t'` prepends.


### Structured Build Logs & Observability
- **Structured Build Logs (`build_log(p)`)**: Expose the underlying Nix build results as a `VBuildLog` record containing node-by-node details, total duration, and a list of failed nodes. `build_pipeline(p)` now returns a `BuildLog` value instead of a raw output-path string (use `build_pipeline(p).out_path` when you need the previous path value).
- **Build Tabulation (`build_log_to_frame`)**: Added `build_log_to_frame(log)` to tabulate build results (one row per node) for high-level analysis using `colcraft` verbs.
- **Accurate Build Log Status Reconciliation**: Refactored the OCaml Nix builder to automatically reconcile all unfinished nodes remaining in `"Pending"` or `"Building"` states to `"Skipped"` when the nix-build process crashes/fails, avoiding confusing out-of-date states.
- **Dynamic Build Log Summaries**: Upgraded `VBuildLog` stringification and REPL pretty-printing to dynamically count and print all status types (e.g. `2 succeeded, 9 failed, 3 skipped`) rather than assuming a simple binary success/failure count.
- **Exception Collection (`collect_exceptions(p)`)**: Gathers all `VError` values and warning diagnostics from computed nodes of a built pipeline into a structured DataFrame (`node`, `status`, `code`, `message`), replacing the legacy `collect_errors` and `error_summary` functions.
- **Traceback cleaning in `collect_exceptions(p)`**: Automatically cleans and extracts the last non-empty line of multi-line error traces (such as from Python or Arrow exceptions) and truncates the string to 100 characters max, maintaining a neat, legible table in the REPL.
- **Polymorphic error functions**: Made standard `error_code()`, `error_msg()`, and `error_context()` builtins polymorphic. They now accept either standard `Error` objects or first-class pipeline `ComputedNode` values (e.g. `p.X` or `p.combined_df`). They automatically resolve the node's underlying `VError` store artifact for soft-failures, or fall back to parsing log traceback details for hard Nix-build failures.
- **Warning Introspection**: Added a new built-in function `warning_msg()` and a matching `.warning_msg` property lookup on computed nodes to easily inspect non-fatal build warnings from successful derivations.
- **Upstream captured errors in `t_make()`**: Upon early termination/build crash, the Nix builder scans the store paths of completed upstream nodes to extract soft-failed diagnostic states, printing them directly in the final build failure summary (e.g. showing `(8 captured errors)` and listing their node names).
- **Polars-Style DataFrame print truncation**: Tabular pretty-printing of all DataFrames in the REPL now automatically truncates cell strings exceeding `35` characters to `32` characters followed by `...` to keep columns aligned and clean.
- **Error Chaining (`error_chain(err1, err2)`)**: Chains multiple errors to preserve failure provenance and causality across dependent nodes.

### Immutable Keyword & Built-in Overwrite Protection
- **Reserved Keyword & Built-in Immutability**: Core built-ins and standard package functions (such as `build_log`, `print`, `mean`, etc.) are now strictly protected against accidental user reassignment or overwriting.
- **Actionable Error Messaging**: Attempting to overwrite a core keyword or built-in function using `=` or the overwrite operator `:=` will raise a highly visible `NameError` (e.g. `Cannot overwrite build_log: it's a reserved keyword!`).
- **Resilient Package Scoping**: The package loader automatically isolates local definitions from standard library origins, allowing package developers to define functions (like `mean`) in their package scope without conflict.

### Julia ONNX Serialization & Parity
- **Dynamic Tape Workarounds**: Implemented dynamic handlers for `:Cast` (pass-through `identity`) and `:Reshape` (handling inferred `-1` shapes mapping to Julia `Colon()`) operators.
- **World Age Resilience**: Wrapped deserialized model loading in `Base.invokelatest` to resolve world age lexical method updates in isolated Nix builds.
- **Dynamic Package Support**: Integrated the `Umlaut` dependency into `[jl-dependencies]` and corrected column-major tracing dimension layouts.

### Compiler Strategy Dictionaries
- **Type-Safe Serialization Registry**: Fixed OCaml type-mismatch bugs in OCaml `nix_emit_node.ml` (`get_format`) and `builder_populate.ml` (`extract_format`) to correctly parse `VSerializer` values inside pipeline deserialization mapping dictionaries (e.g., `deserializer = [ julia_model: ^onnx ]`).

### End-to-End Stress Testing & CI
- **Polyglot Parity Scoring**: Added the `onnx_julia_stress_t` and `observability_hardening_t` end-to-end stress test suites to verify prediction parity, safety safeguards, and observability logs.
- **Automated Workflows**: Created premium automated GitHub Actions CI workflows to run these suites on PR and push events.

### Documentation Corrections
- **Removed `jn()` alias**: Eliminated the undocumented `jln()` alias `jn()` from the evaluator, tests, and all documentation. Use `jln()` exclusively for Julia pipeline nodes.
- **Corrected Node-Family `Returns` docs**: All node-defining functions (`node`, `rn`, `pyn`, `jln`, `qn`, `shn`) now correctly document their return type as a `NodeDef` pipeline node configuration object, not the evaluated result of the enclosed code. The code is executed by `build_pipeline()`, not immediately.
- **Corrected `jln` serializer default**: Documentation previously stated the default serializer was `^csv`; the actual default is the runtime-native binary serializer (`jl_serialize`), consistent with `rn` and `pyn`.

## [0.52.0] "Kaméhaméha" - 2026-05-18

The focus of this release is the introduction of first-class Julia support, enabling high-performance polyglot pipelines with seamless Julia integration.

**Status**: Beta

### First-Class Julia Support
- **Julia Node Shorthand (`jln`)**:
    - Introduced `jln()` for executing Julia code directly within T pipelines.
    - Julia nodes support full dependency management and automatic environment provisioning.
- **Integrated Dependency Management**:
    - Projects can now declare Julia requirements in `tproject.toml` via the `[jl-dependencies]` section.
    - Support for specific Julia versions and automatic Nix-based environment generation.
- **Native PMML Support**:
    - Full support for PMML model scoring and export within Julia nodes using the `^pmml` serializer.
    - High-performance in-memory scoring via `JavaCall.jl` integration.
- **Native ONNX Support**:
    - Full support for ONNX model inference and export within Julia nodes using the `^onnx` serializer.
    - Leverages `ONNXRunTime.jl` for industry-standard inference performance and `ONNX.jl` for model serialization.
- **Enhanced Polyglot Ergonomics**:
    - Simplified data interchange between T, R, Python, and Julia.
    - Improved automatic dependency discovery for Julia packages used within pipeline nodes.
    - Robust system-level library resolution for complex Julia dependencies (like JVM and ONNX runtimes) within the Nix sandbox.
- **World Age Resilience**:
    - Implemented a robust fix for Julia's "World Age" issues (e.g., `MethodError: method is too new`).
    - The Julia node emitter now wraps script execution in a high-level thunk and executes it via `Base.invokelatest`.
    - This ensures that code generated at runtime (common in libraries like `Flux.jl` or `Zygote.jl`) remains accessible within the same execution cycle, even in restricted environments like the Nix build sandbox.
- **Julia JSON Interchange**: Added support for the `JSON` package in Julia nodes, enabling seamless JSON-based data exchange for Julia-based pipeline steps.
- **Julia Plotting Enhancements**: 
    - `show_plot()` now supports Julia plots via `TidierPlots.jl`, `Plots.jl`, and `Makie.jl`.
    - **CairoMakie Requirement**: For `Makie.jl` objects, `CairoMakie` is the mandatory backend for reproducible headless rendering within the Nix sandbox. Ensuring `CairoMakie` is in `[jl-dependencies].packages` is required for successful visual inspection of Makie nodes.

### External Helper Packages (R, Python, Julia)
- **New `read_node` Helpers**: Introduced lightweight packages for R, Python, and Julia (all named `tlang`) to simplify consumption of T-Lang build artifacts from external runtimes.
- **Programmatic DAG Inspection**: Added `pipeline_nodes()` to all companion packages. It returns the pipeline DAG as an idiomatic data structure (e.g., `data.frame` in R, `dict` in Python/Julia), enabling easy programmatic traversal of node relationships.
- **Refactored Pipeline Diagnostic Output**:
    - Removed the redundant `path:` field from the default `ComputedNode` REPL printer.
    - The default REPL printer no longer displays `path: <unbuilt>` / `path:` status lines for `ComputedNode`s; users who need explicit artifact paths in the T runtime can obtain them via `inspect_node(node).path` or `inspect_log()`.
- **Support for `return_path` in Companion Packages**: Added `return_path` argument to `read_node()` in the R, Python, and Julia companion packages. When set to true, these helpers return the absolute path to the artifact in the Nix store/project directory instead of deserializing it, allowing for custom loading logic or direct file inspection.
- **Automated Log Resolution**: These helpers now automatically resolve the most recent `build_log_*.json` in the `_pipeline/` directory, providing a stable way to access node results during development and reporting (e.g., in Quarto).
### Strict Serialization & Pipeline Stability
- **Symbol-Mandated Serialization**: 
    - Mandated the use of `^` symbols for node serializers and deserializers (e.g., `serializer = ^arrow`). 
    - String literals are now strictly disallowed in these fields and will trigger a descriptive `TypeError` during evaluation, eliminating a common source of pipeline configuration drift.
- **Opaque Error Elimination**:
    - Enhanced `write_arrow` to surface detailed `VError` traces instead of failing silently.
    - Pipeline nodes now report the actual root cause (including tracebacks) from upstream failures, making debugging polyglot pipelines significantly faster.
- **Standard Package Registry**:
    - Registered `dataframe` as a core standard package, ensuring stable resolution during Nix builds and preventing "package not found" errors in isolated environments.
- **R Factor Stability**: Fixed a regression in R nodes where the standardized `to_factor` was being incorrectly emitted; now correctly uses the standard R `factor()` for native R-node interoperability.
### API Standardization & Ergonomics
- **Unified `to_` Naming Convention**:
    - Renamed all type conversion and coercion functions to follow a consistent `to_` prefix:
        - `as_date()` → `to_date()`
        - `as_datetime()` → `to_datetime()`
        - `as_factor()` / `factor()` → `to_factor()`
        - `sym()` → `to_symbol()`
        - `dataframe()` → `to_dataframe()`
        - `str_string()` → `to_string()`
    - Removed all legacy `as_*` and shorthand aliases (`fct()`, `fct_infreq()` → `to_factor(..., ordered=true)` etc.) to ensure a single, canonical API path.
- **Renamed Statistical Diagnostics**:
    - `augment()` renamed to `add_diagnostics()` for better clarity and consistency with the T-Lang philosophy of descriptive names.
- **Refined Data Converters**:
    - `to_string()` now provides a unified interface for string conversion across all T types, including proper level resolution for Factors and recursive formatting for Lists and Vectors.
- **Improved Factor Creation**:
    - Removed the `fct()` shorthand in favor of the standardized `to_factor()`.
    - Simplified factor logic: `to_factor()` now consistently uses alphabetical sorting for derived levels, removing the previous "first-appearance" behavior to align with industry standards and internal consistency.
- **Descriptive Statistical Utilities**:
    - Renamed `augment()` to `add_diagnostics()` to better reflect its purpose of appending model-level diagnostics (residuals, hat values, etc.) to data frames.
    - Updated the Golden test suite to maintain parity with R's `broom::augment` outputs.
- **Codebase & Demo Synchronization**:
    - Performed a repository-wide refactor of 65+ demo projects in `t_demos` to adopt the new standardized API.
    - Updated Tree-Sitter syntax highlighting queries to support the new names and remove deprecated aliases.

## [0.51.5] - 2026-05-08

The focus of this release was to improve language ergonomics for data guardrails, enhance package manager feedback, and increase test coverage across all packages.

**Status**: Beta  

### Performance & Arrow FFI
- **Native Table Nesting & Unnesting**:
    - Implemented a zero-copy native Arrow FFI pipeline for `nest()` and `unnest()` operations to eliminate OCaml-side materialization bottlenecks.
    - Optimized `GroupedTable` to use `gint64` row indices, enabling direct bulk transfer of group subsets to Arrow.
- **Native Vertical Concatenation**:
    - Introduced high-performance native vertical concatenation for Arrow-backed tables, significantly reducing memory overhead when stacking large data chunks.
- **Native Horizontal Merging**:
    - Added native support for merging columns between two tables directly in Arrow memory (`merge_horizontal`), enabling efficient expansion of key columns during unnesting.

### Package Management & User Feedback
- **Improved Dependency Sync Messages**:
    - Enhanced `t update` feedback to explicitly report counts for R, Python, Additional Tools, and LaTeX packages being synchronized to `flake.nix`.
    - Introduced context-aware "No T dependencies" messages that accurately reflect when a project still defines other runtime requirements (R/Python/Tools).
    - Verified message formatting logic with new unit tests for tools-only and polyglot project configurations.

### Language Ergonomics
- **Default Value Support in `get()`**: Enhanced the `get()` primitive to support default value fallbacks. It now handles:
    - `get(potential_error_or_na, default)`: Returns the default if the first argument is an error or NA.
    - `get(target, selector, default)`: Returns the default if the retrieval from the target fails.
    - This enables concise and safe data guardrails, such as `get(s.min_age, 0) >= 0`, which gracefully handles missing columns or empty summaries.

### Quality & Test Coverage
- **Expanded Stats Package Coverage**:
    - Enhanced ONNX test coverage by adding a Decision Tree Classifier test suite.
    - Fixed `generate_onnx.py` compatibility with scikit-learn 1.6+ and ensured numeric output parity for classification models.
    - Stabilized PMML prediction golden tests by tightening the random-forest regression tolerance to `1e-2` to preserve cross-runtime stability without masking meaningful regressions.
    - Added comprehensive golden tests for 15+ specialized statistical functions, probability distributions, and transformations.
    - **Specialized Metrics**: Verified `cv`, `fivenum`, `trimmed_mean`, `mad`, `iqr`, `range`, `var`, and `cov` against R baselines.
    - **Advanced Moments**: Added coverage for `skewness` and `kurtosis` (excess kurtosis) using population-moment calculations.
    - **Probabilistic Distributions**: Added golden tests for `pnorm` (standard normal approximation), `pt`, `pf`, and `pchisq` CDFs.
    - **Statistical Operations**: Verified `winsorize`, `huber_loss`, `normalize`, and Pearson `cor` against R reference values.
    - **Weighted Statistics Support**:
        - Implemented the `weights` argument for `lm()` to support Weighted Least Squares (WLS) regression.
        - Added support for weighted versions of `mean`, `sd`, `var`, `cov`, `cor`, `median`, `quantile`, `iqr`, `fivenum`, `trimmed_mean`, `skewness`, and `kurtosis`.
        - Verified accuracy and diagnostic consistency across the statistical package.
    - **Data Transformations**: Added a golden test for `standardize` and `scale` using `iris$Sepal.Length`.
    - **Model Accessors**: Added regression tests for `coef`, `conf_int`, `sigma`, `nobs`, and `df_residual` for linear models.
- **Cross-Platform Stability**:
    - **Darwin Portability**: Fixed non-portable shell behavior and path symlink inconsistencies in `builder_utils.ml` and `test_misc_coverage.ml`. Switched to `Unix.realpath` for canonical path resolution on macOS (handling `/var` vs `/private/var`) and ensured GNU utilities are explicitly used via Nix environment wrappers.
- **Critical Fixes & Statistics Parity**:
    - **ONNX Input Alignment**: Synchronized the native ONNX evaluator with regenerated model fixtures, updating expected input metadata from `X` to `float_input` to match `scikit-learn` 1.6+ exports.
    - **Metadata Parity**: Injected `model_type` and `mining_function` metadata into `lm` and PMML-loaded model objects. This ensures that `fit_stats()` returns complete, R-compatible diagnostic tables without `NA` placeholders for model categories.
    - **Enhanced `anova`**: Updated the `anova` builtin to support model labels (e.g., `anova(m1 = m1, m2 = m2)`). The labels are now preserved in the resulting DataFrame, matching R's behavior in model comparison tables.
    - **Quantile Accuracy**: Fixed a critical bug in the C-based quantile implementations (`normal_quantile`, `t_quantile`) where tail approximations were incorrect, leading to broken confidence intervals. Implemented high-precision Acklam's algorithm for normal quantiles and accurate Cornish-Fisher expansion for $t$ quantiles.
    - **Test Runner Stability**: Suppressed noisy `onnxruntime` CPU vendor warnings in the golden test suite and standardized the "✓" success indicator across all statistical test scripts.
    - **PMML Prediction Consistency**: Resolved floating-point discrepancies in PMML random forest regression predictions by implementing standard tolerances in the golden test suite, ensuring cross-environment test reliability.
- **Improved Base Package Coverage**:
    - Significantly increased test coverage for `base` package builtins, specifically targeting error handling, NA container logic, and serialization.
    - **NA Mapping**: Verified `is_na` vectorization across Vectors and named Lists.
    - **Serialization Robustness**: Added comprehensive error-path testing for `serialize`, `deserialize`, `t_write_json`, and `t_read_json`, including type-mismatch and file-system failure scenarios.
- **Improved Core Package Coverage**:
    - Expanded test coverage for `core` package builtins, including `args`, `help`, `apropos`, and `write_text`.
    - **Introspection**: Added tests for the `args()` builtin on both builtins and lambdas, ensuring correct parameter name and type extraction.
    - **Core Unit Tests**: Expanded coverage for `identical` (deep equality), `sum` (edge cases), `seq` (auto-descending ranges), and `head`/`tail` (slicing boundaries).
    - **Coverage Boost**: Significantly increased coverage for `ifelse`, `case_when`, and `identical` (t_boolean.ml), `get` with all lens types (t_get.ml), and all specialized rendering paths in `pretty_print.ml`.
    - **Coverage Integration**: Added the new colcraft coverage tests to the test runner so these scenarios are exercised in regular test execution.
    - **Colcraft Coverage**: Expanded testing for `fill`, `replace_na`, `complete`, `relocate`, `count`, `slice`, `unnest`, `separate`, and `uncount`. Verified `downup` direction logic and regex error handling.
    - **Pretty Printing**: Verified nested collection and visual metadata (Altair) rendering in `pretty_print`.
    - **Help System**: Added regression coverage for invalid input types and missing-documentation cases in `help()` and `apropos()`.
- **Improved Lens Package Coverage**:
    - Significantly increased test coverage for the `lens` package, focusing on custom lenses, pipeline orchestration, and recursive mapping.
    - **Custom Lenses**: Added coverage for Dictionary-based lenses with user-defined `get` and `set` functions.
    - **Pipeline Orchestration**: Verified `node_meta_lens` for `serializer` and `deserializer` fields, and `filter_lens` for batch updates to pipeline node values.
    - **Recursive Mapping**: Added tests for `col_lens` and `idx_lens` across nested Lists of Vectors and DataFrames.
    - **Resilience**: Verified error propagation and halt-on-failure behavior in the variadic `modify()` builtin.
- **Enhanced Arity Error Reporting**:
    - Updated the core evaluator to include function names in arity error messages for all builtins (e.g., `Function `length` expects...`).
    - Standardized arity error expectations across the entire test suite (1944/1944 tests passing).
- **Developer Experience & Coverage Tools**:
    - **Nix-based Coverage**: Introduced the `packages.t-coverage` Nix output for simplified code coverage collection.
    - **Instrumentation Isolation**: Fixed coverage baseline contamination by isolating documentation generation during the Nix build process.
    - **Integrated Reporting**: Bundled `bisect-ppx-report` within the coverage derivation to streamline local reporting workflows.

## [0.51.4] - 2026-04-30

**Status**: Beta  

### AI Agent Onboarding & Context Tiering
- **Tiered Language Reference**:
    - Introduced a tiered system for language reference files (`small`, `medium`, `full`, `huge`).
    - **`huge` reference generation**: Implemented a recursive build process in `docs/build.sh` that concatenates the entire documentation ecosystem into a single, comprehensive reference for high-context agents.
- **Interactive Scaffolding**:
    - Updated `t init` to be fully interactive. The CLI now prompts for the **AI Agent Context Level** during project or package initialization.
    - **`AGENTS.md`**: Automatically generates project-specific onboarding guides for LLMs based on the workspace type.
    - **Automated Deployment**: The chosen reference level is deployed as `T-LANGUAGE-REFERENCE.md` in the project root and automatically added to `.gitignore`.
- **LLM-First Documentation**:
    - Updated the `README`, `Getting Started`, and `LLM Collaboration` guides to emphasize T's unique support for agentic development.

### Language Ergonomics & Auto-Quoting
- **Auto-Quoted Parameters (`$param`)**: 
    - Introduced `$param` syntax in lambda and `function()` parameter lists.
    - Parameters prefixed with `$` automatically capture bare names (like column names) as **Symbols** rather than evaluating them.
    - Simplified the creation of data-wrangling wrappers, removing the need for `enquo()` in simple forwarding cases.
- **Unified `get()` and New `to_symbol()` Builtin**:
    - Added the `to_symbol()` core builtin for programmatic symbol creation.
    - Unified the `get()` dispatcher across `core` and `lens` packages, ensuring a single, stable interface for variable lookup, collection indexing, and lens-based retrieval.
    - **Regression Safety**: Added regression tests to ensure core primitives remain stable when the `lens` package is loaded.

### Structural Integrity & Terminal Error Handling
- **Introduced `StructuralError` Category**:
    - Added `StructuralError` as a new terminal diagnostic code for fundamental pipeline orchestration failures.
    - **DAG Validation**: Dependency cycles, self-referential nodes, and missing sibling node references are now classified as `StructuralError`.
    - **Orchestration Failure**: Materialization errors in `populate_pipeline` (e.g., missing dependencies in `tproject.toml`, missing Nix build tools, or stalled artifact directories) now emit `StructuralError`.
- **Terminal Evaluation Policy**:
    - The core evaluator now treats `StructuralError` as a **terminal event** that bypasses "Resilient-by-Default" (`resilient=true`) settings.
    - This ensures that fundamental infrastructure or topology breaks stop script execution immediately, preventing confusing downstream "cascading gibberish" errors while maintaining resilience for standard data-computation errors (like `1 / 0`).
- **Environment-Aware Failures**:
    - Pipeline dependency checks now respect the `TLANG_AUTO_ADD_PIPELINE_DEPS` environment variable.
    - If auto-injection is disabled or impossible (non-interactive sessions), the system raises a fatal `StructuralError` instead of implicitly continuing into a broken Nix state.

### Pipeline Infrastructure & Lens Orchestration
- **Resolution Stabilization**:
    - Implemented robust lazy resolution for cross-pipeline dependencies and out-of-order pipeline nodes.
    - Fixed a regression where pipeline nodes were returning `unbuilt` states instead of resolved values in complex dependency graphs.
- **Improved Failure Visibility**:
    - Introduced structured `MissingArtifactError` in the lens system to provide precise feedback on unbuilt dependencies during lazy evaluation.
    - Clarified the error contract for `get()` when targeting plotting nodes, ensuring metadata dictionaries are returned predictably.

### First-Class Visual Metadata & Plot Inspection
- **Automated Plot Metadata Capture**: 
    - Implemented infrastructure to automatically extract and persist metadata from visual objects in polyglot pipelines.
    - **R Support**: Capture titles, labels (x, y, color, etc.), mappings, and layers from `ggplot2` objects.
    - **Python Support**: Full metadata extraction and inspection support for `matplotlib` figures, `plotnine` (ggplot-style), `seaborn` grids, `plotly` figures, and `altair` charts.
- **Enhanced `show_plot()` Builtin**:
    - Introduced `show_plot()` to render and open pipeline plot artifacts locally.
    - Supports automatic rendering of R (`ggplot2`), Python (Matplotlib, Seaborn, Plotly, Altair, Plotnine), and Julia (`TidierPlots.jl`, `Plots.jl`, `Makie.jl` via `CairoMakie`) plots within the Nix sandbox.
    - Implemented headless rendering for interactive libraries: Plotly (via `kaleido`) and Altair (via `vl-convert`).
    - **Dependency Automation**: `tlang` now automatically suggests or injects `cloudpickle` when plotting libraries are detected in Python nodes to ensure reliable serialization of complex objects containing lambdas.
- **Transparent `read_node()` for Plots**:
    - `read_node()` now recognizes nodes of class `ggplot`, `matplotlib`, `plotnine`, `seaborn`, `plotly`, `altair`, `tidierplots`, `plotsjl`, or `makie`.
    - Instead of returning an opaque binary artifact, it returns a structured JSON-backed dictionary of the plot's metadata, enabling programmatic verification of visualizations in T scripts.

### Serializable Lens Architecture
- **Refactored Lens Implementation**:
    - Replaced functional closure-based lenses with a structured `VLens` sum type.
    - **Nix-Isolated Persistence**: Lenses can now be serialized to disk and passed between separate Nix-build pipeline nodes without losing their state or functionality.
    - **Unified `get()` Integration**: The `get()` builtin now natively supports `VLens` for data focus, providing a single, consistent interface for variable lookup, indexing, and lens-based retrieval.

### Core Evaluator, Emitter & Documentation Refinements
- **Improved Docstring Coverage**: Added full T-style documentation (descriptions, parameters, examples) for `get()`, `to_symbol()`, and related primitives.
- **Integrated Documentation Tooling**: Verified `t_doc("parse")` and `t_doc("generate")` workflows for extracting and publishing reference pages for new core functions.
- **Auto-Quoting Documentation**: Updated `docs/language_overview.md` and `docs/quotation.md` with comprehensive examples of the new `$param` auto-quoting feature.

### Editor Support & Tree-sitter
- **Official Tree-sitter Grammar**:
    - Introduced a formal Tree-sitter grammar for T in `editors/tree-sitter-t`.
    - Supports robust syntax highlighting, local scope resolution, and language injections.
    - **Polyglot Injections**: Automatically injects R, Python, and Bash syntax highlighting into `<{ }>` blocks when used inside `rn()`, `pyn()`, or `shn()` calls (supporting both named and positional arguments).
    - **Expanded Highlighting**: Highlighting coverage expanded to include ~140+ standard library functions across all core packages.
    - **Editor Integration**: Added documentation and configuration examples for Neovim, Emacs 29+, VS Code, and other Tree-sitter compatible editors.
### Core Evaluator & Emitter Refinements
- **Quarto Wrapper Ergonomics**: Added `qn()` as a first-class convenience wrapper around `node()` with `runtime = Quarto`, matching the existing `rn()` and `pyn()` helpers for R and Python nodes.
- **Improved Pretty Printing**: Updated the core pretty printer to handle complex nested dictionaries and diagnostics summaries more gracefully.
- **Nix Emitter Stability**: Significant updates to `nix_emit_node.ml` to support the new visualization injection logic and improve script-based node robustness.
- **Test Infrastructure**: Added the `get_sym_demo_t` comprehensive demo project with dedicated CI validation and automated assertions.

### Bug Fixes & Refinements
- **Visualization Stability**: Fixed a critical `Printf.sprintf` type error in the Python plot rendering logic that prevented pipeline builds for Python-based visualizations.
- **Improved REPL interaction**: Explicitly flush stdout/stderr around `show_plot` calls so the rendered path is reported cleanly before local viewer launch.
- **Helper Consistency**: Standardized lens helper names and improved internal consistency in `lens.ml`.
- **Pipeline Predicate Scoping**: Fixed a regression where `filter_node(is_na($diagnostics.error))` and `which_nodes(is_na($diagnostics.error))` could evaluate outside the node metadata scope and incorrectly exclude nodes without diagnostics errors.


### Resilient-by-Default Evaluation
- **Global Resilience**: Evaluation now defaults to resilient mode (`resilient=true`). This ensures that scripts and pipelines continue execution upon encountering `VError` values, aligning with the "Errors are Values" philosophy.
- **`--failfast` Flag**: Replaced the `--resilient` CLI flag with `--failfast`. Users can now explicitly opt-in to the usual, common behaviour of short-circuiting upon the first error.
- **`t_make()` & `t_run()` Integration**: Added `failfast` parameter to the main pipeline orchestrator and script runner for granular control.
- **Improved Serialization Restoration**: Fixed a critical bug where `VError` values were deserialized as Dictionaries. The system now correctly restores the native `Error` type across node boundaries, even when using modern JSON interchange.

## [0.51.3] - 2026-04-12

**Status**: Beta  

### Pipeline Infrastructure & Observability
- **First-Class Diagnostics Engine**: 
    - Implemented a comprehensive diagnostics system that captures and classifies "own" vs. "upstream" warnings.
    - Pipeline builds now persist non-terminal warnings and terminal errors as node artifacts.
    - **Soft-Fail Semantics**: Internal node failures no longer halt the entire Nix build; they produce `VError` objects, allowing independent branches to complete.
    - **Diagnostic Suppression**: Introduced `suppress_warnings` combinator to silence high-noise nodes while maintaining background auditability.
    - **Improved Summaries**: Updated build summaries to use plural-safe `node(s)` and `error(s)` formatting, with clear iconographic reporting (`✖`, `✓`, `○`, `?`).
- **Enhanced Interrogation Tools**:
    - **`read_node()` & `read_pipeline()`**: Promoted to first-class tools. They now accept in-memory objects and return structured results with values and diagnostics.
    - **`explain()` function**: Enhanced to surface context, tracebacks, and missingness statistics for pipeline results and errors.
    - **Verbose Logging**: Added `verbose=1` support to pipeline builders, mapping directly to Nix build logs for improved debugging.
- **Architectural Improvements**:
    - **Lazy Evaluation**: Implemented lazy cross-pipeline dependency resolution, allowing expressive and ergonomic pipeline composition.
    - **Resilient Path Resolution**: Fixed repository root discovery for nested builds and Nix sandboxes.
    - **Dependency Traceability**: Automatic injection of `node_name` into all diagnostic records for clear error attribution in complex DAGs.

### Standardized Missingness & "Death to Null"
- **Comprehensive NA Enforcement**:
    - Finalized the T-Lang NA specification for total "No Silent Magic" compliance.
    - **`NAPredicateError`**: Dedicated error code for NA values in boolean contexts, enabling robust logic in `filter()` and `if` expressions.
    - **Strict Guards**: Enhanced logical and comparison operators to raise errors on NA instead of silent propagation.
    - **Optimized Math**: Verified `na_ignore` semantics across all core math transforms (`abs`, `log`, `sqrt`, `exp`, `pow`) and aggregations (`min`, `max`, `sum`, `mean`).
- **Complete Removal of Null**:
    - The `null` keyword and `VNull` type have been completely removed from the language grammar and AST.
    - Unified all previous "nullable" return paths (e.g., missing env vars, empty nodes) to use typed `NA` values.
    - Replaced `is_null()` with `is_na()` as the universal missingness predicate.

### Model Interoperability & Native Scoring
- **Standardized PMML Interchange**:
    - Transitioned to JPMML as the canonical scoring authority via a robust, CSV-based bridge.
    - **Native Ensemble Scoring**: Added native OCaml support for Random Forests, XGBoost, and LightGBM models.
    - **Categorical Expansion**: Implemented automatic dummy-variable/one-hot expansion and interaction term (`:`) resolution in the native `lm()` and `predict()` engines.
    - **`fit_stats()` API**: Unified goodness-of-fit statistics (R², AIC, BIC) into a single, language-agnostic DataFrame output.
- **Native ONNX Inference**:
    - Full support for `^onnx` serialization and native OCaml scoring via `onnxruntime` FFI.
    - Automated feature mapping, metadata extraction, and multi-input/output tensor support.
    - High-performance, memory-safe session management with OCaml GC integration.

### Language Robustness & Interop
- **Strict Equality Semantics**:
    - Enforced scalarity for `==` and `!=`. These now require explicit broadcasting (`.==`) for collections to prevent silent logic errors.
    - **`identical(a, b)`**: New core builtin for deep structural equality of complex objects.
- **Enhanced Data Operations**:
    - **`to_dataframe()` Constructor**: Added support for Dictionary-based construction and automatic scalar recycling.
    - **NSE Safety**: Implemented guarded NSE transformation to prevent unexpected lambda-wrapping of non-NSE builtins.
- **String Column Extraction**: Enhanced `pull()` and column helpers to support `VString` arguments for extraction of special-character column names.

### Project, CI & Test Infrastructure
- **Strict Dependency Declaration**:
    - Finalized the removal of implicit Nix package injection. All requirements must be explicitly listed in `tproject.toml`.
    - Added interactive injection prompts and `TLANG_AUTO_ADD_PIPELINE_DEPS` for CI automation.
- **Environment Stability**:
    - Standardized Nixpkgs pinning via `RSTATS-NIX-DATE` for reproducible, cache-friendly builds.
    - **Serialization Integrity**: Introduced mandatory MD5 digests for all serialized artifacts.
- **CI/CD Stabilization**:
    - Refactored `t_demos` into 30+ dedicated per-demo workflows.
    - Optimized the core test suite to use static interrogation and modern mocks, achieving a stable baseline of **1837/1837** tests passed.
    - Enhanced the test runner with aggregated failure summaries.

### Bug Fixes & Refinements
- **REPL Stability**: Corrected a documentation comment collision in `repl.ml` that was causing compilation errors during scale-wide refactors.
- **Python Node Emitter**: Refined the auto-return logic to ignore trailing comments and whitespace, preventing silent `None` results.
- **Grouped Mutate**: Fixed a regression where assigning constant scalars to grouped DataFrames would fail.
- **Interaction Resolution**: Restored and verified interaction term (`:`) resolution in native linear model scoring.

## Version 0.51.2

**Status**: Beta  
**Release Date**: 2026-03-28

### Features & UX

- **Immutable Update Lenses**: F inalized the lens system with support for deep surgical updates to Dictionaries and DataFrames.
    - Introduced **`modify()`**: A variadic builtin for applying multiple lens transformations in a single pass.
    - Updated **`compose()`**: Now variadic, allowing any number of lenses to be chained into a single declarative path.
    - **Orchestration Lenses**: Added `node_lens()` and `env_var_lens()` for inspecting and modifying Pipeline node results and environment variables.
    - **Collections & Filtering**: Added **`idx_lens(i)`** for positional access in Lists/Vectors, **`row_lens(i)`** for specific DataFrame row targeting, and **`filter_lens(p)`** for predicate-based focus on elements and rows.
    - **Vectorization**: Lenses are fully vectorized, allowing transformations to penetrate nested DataFrames across all rows automatically.
- **`rm()` Function**: New core language feature for removing variables from the environment. Supports symbols, strings, and list-based removal (e.g., `rm(x, y)`, `rm("z")`, `rm(list = vars)`).
- **Asynchronous Build Progress**: Implemented a new streaming build progress reporter in the terminal. Pipeline builds now show real-time "building" and "built" alerts for each node, with high-noise Nix logs filtered by default.
- **First-Class Serializer System**: Introduced a robust, type-safe serialization layer for polyglot pipelines.
    - **Serializer Registry**: Added the `^` symbol prefix for resolving built-in serializers from a centralized registry (e.g., `^csv`, `^arrow`, `^pmml`, `^json`, `^text`).
    - **VSerializer Type**: Serializers are now first-class records containing metadata and language-specific snippets for R and Python.
    - **Foreign Code Enforcement**: Custom polyglot serializers now require foreign code blocks (`<{ ... }>`) for reader/writer snippets, ensuring syntactic separation between T and injected code.
    - **Static Coherence Checks**: The pipeline builder now performs build-time verification to ensure producer and consumer formats match, catching data interchange errors before execution.
- **Error Visibility**: When a pipeline fails, the summary now correctly reports the count of errored nodes (e.g., "[1 node errored]").
- **REPL Interface**: Added a new `t_make()` builtin to the REPL. It defaults to building `src/pipeline.t` and supports optional named arguments (e.g., `max_jobs`, `max_cores`) that pass through to the underlying Nix build.
- **Improved Name Errors**: Added fuzzy matching to `NameError` reporting with "Did you mean ...?" suggestions when an unbound variable is accessed.
- **Pattern Matching (match)**: Introduced the `match` expression for declarative list and error destructuring. Includes support for head/tail patterns, `Error { msg }` patterns, and automatic error propagation for unhandled error values.
- **REPL Responsiveness**: Added explicit `flush stderr` after variable reassignment (`:=`) warnings to ensure they appear promptly in the REPL.
- **Pipeline Sandboxing**: Enhanced `read_node()` to automatically fall back to environment variables (`T_NODE_<name>`) when build logs are unavailable. This enables `read_node` to work inside Nix build sandboxes (e.g., within Quarto nodes or nested pipeline steps) and provides automatic deserialization for Arrow, JSON, and PMML artifacts based on class hints.

### Improved

- **Build Log Inspection**: `read_log()` now returns the Nix build log as a `VString` instead of printing directly. This allows the log to be captured as a variable or formatted with `cat()`.
- **String Printing**: `print()` and `cat()` now correctly handle literal newlines and escape sequences in strings and shell results, ensuring `?<{ls -l}>` and logs display correctly.
- **Project Initialization**: Better `t init` interactive prompts and project scaffolding templates. The `t init` command now defaults to the version of the T binary being used.
- **CLI Interface**: Renamed `t init package` and `t init project` subcommands to `t init --package` and `t init --project` flags for better clarity.
- **Python Node FFI**: Improved dependency handling in `pyn()`. Pipeline nodes are now correctly provided as global variables in the Python runtime.
- **Nix Sandbox Robustness**: Added missing `import os` to Python serialization snippets, ensuring standard library access in the Nix sandbox.
- **CI Reliability**: `t update` now automatically handles untracked `flake.nix` in Git repositories when running in a CI environment (`CI=true`).
- **Nix Support**: Added help for experimental flags and trusted user configuration in `docs/installation.md`.

### Fixed

- **Design Consistency**: Standardized all documentation and examples to reinforce the "**Data Frame First**" principle for function arguments, ensuring compatibility with T's functional piping (`|>`) patterns.
- **Typos**: Fixed documentation typos (e.g., "sterilization" -> "serialization").
- **Example Revisions**: Synchronized all pipeline demos in `t_demos` and `examples/` with the latest first-class serializer system and `^`-prefix notation.
- **Error Message Clarity**: Improved error messages for immutable variable reassignment with actionable suggestions (`Use ':=' to overwrite or rm() to delete the variable`).
- **Global Guide Alignment**: Performed a repository-wide sweep to remove legacy version strings and hardcoded formatting in installation and project guides.

Version history and roadmap for the T programming language.

## [0.51.1] - 2026-03-21

**Status**: Beta
**Release Date**: 21st of March 2026

### Features & CLI

- **New Command**: Introduced `t upgrade` to automatically update projects to the latest T version and refresh the `rstats-on-nix` nixpkgs date.
- **Centralized Versioning**: Version is now managed in a single `VERSION` file and propagated across the project.

### Bug Fixes & Improvements

- **Package Management**: Fixed issues in `t update` and related flake generation logic.
- **Quarto Integration**: Fixed `read_node` substitution in Quarto reports to prevent syntax errors in R/Python chunks.
- **Testing**: Resolved failures in Quarto pipeline tests and improved CI reliability.

## Version 0.51.0 — First Public Release

**Status**: Alpha — Syntax and semantics frozen  
**Release Date**: February 2026

### Package Manager (`t update`)

- **Versioning sync**: `t update` now generates a `flake.nix` that points to this version by default.
- **Improved defaults**: Projects without an explicit `min_version` now use 0.51.0.

### Language Core

✅ **Implemented**:

- Lexer and parser (Menhir)
- Tree-walking interpreter
- Expression-oriented evaluation
- Immutable values
- Dynamic typing with runtime checks
- First-class functions and closures
- **Non-Standard Evaluation (NSE)**: Dollar-prefix column references (`$column_name`) for concise data manipulation

### NSE (Non-Standard Evaluation)

✅ **Implemented**:

- Dollar-prefix syntax: `$column_name` for column references
- Auto-transformation: `$age > 30` → `\(row) row.age > 30`
- Named-arg syntax: `summarize($total = sum($amount))`, `mutate($bonus = $salary * 0.1)`
- Works with all data verbs: `select`, `filter`, `mutate`, `arrange`, `group_by`, `summarize`

### Data Types

✅ **Implemented**:

- Scalars: Int, Float, Bool, String
- Collections: List, Dict
- DataFrames (Arrow-backed)
- Vectors (typed arrays)
- NA (typed missing values)
- Error (structured errors, not exceptions)
- Pipeline (DAG execution)
- Intent (LLM metadata)
- Formula (statistical modeling)
- NA

### Operators

✅ **Implemented**:

- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`
- Logical: `and`, `or`, `not`
- Pipe: `|>` (conditional, short-circuits on error)
- Maybe-pipe: `?|>` (always forwards, including errors)
- Formula: `~` (for regression models)

### Standard Library

✅ **Core Package**:

- `print`, `pretty_print`, `type`, `length`, `head`, `tail`
- `map`, `filter`, `sum`, `seq`
- `is_error`

✅ **Base Package**:

- `error`, `error_code`, `error_message`, `error_context`
- `assert`
- `NA`, `na_int`, `na_float`, `na_bool`, `na_string`, `is_na`

✅ **Math Package**:

- `sqrt`, `abs`, `log`, `exp`, `pow`
- `min`, `max`

✅ **Stats Package**:

- `mean`, `sd`, `quantile`, `cor` (with `na_rm` parameter)
- `lm` (linear regression: `y ~ x`)

✅ **DataFrame Package**:

- `read_csv` (with `separator`, `skip_lines`, `skip_header`, `clean_colnames`)
- `write_csv`
- `nrow`, `ncol`, `colnames`
- `clean_colnames` (symbol expansion, diacritics, snake_case, collision resolution)

✅ **Colcraft Package** (Data Verbs):

- `select`, `filter`, `mutate`, `arrange`
- `group_by`, `summarize`, `ungroup`
- **Window functions**:
  - Ranking: `row_number`, `min_rank`, `dense_rank`, `cume_dist`, `percent_rank`, `ntile`
  - Offset: `lag`, `lead`
  - Cumulative: `cumsum`, `cummin`, `cummax`, `cummean`, `cumall`, `cumany`

✅ **Pipeline Package**:

- `pipeline_nodes`, `pipeline_deps`, `pipeline_node`, `pipeline_run`

✅ **Explain Package**:

- `explain`, `explain_json`
- `intent_fields`, `intent_get`

### Features

✅ **Error Handling**:

- Errors as values (not exceptions)
- Railway-oriented programming with `|>` and `?|>`
- Actionable error messages with suggestions

✅ **NA Handling**:

- Explicit NA (typed: `na_int()`, etc.)
- No automatic propagation
- `na_rm` parameter for aggregations
- Window functions handle NA gracefully

✅ **Pipelines**:

- DAG-based execution
- Automatic dependency resolution
- Deterministic order
- Cycle detection
- Introspection

✅ **Cross-Language Model Interchange (PMML)**:

- Native PMML parser and evaluator in OCaml
- Seamless import of models from R (`lm`) and Python (`scikit-learn`)
- `broom`-style tidy summaries (`summary()`, `fit_stats()`) for imported models
- Native high-performance prediction in T without runtime language dependencies

✅ **Intent Blocks**:

- Structured metadata for LLM collaboration
- Document assumptions, constraints, goals
- Machine-readable format

✅ **Arrow Integration & Data Formats**:

- Zero-copy columnar storage
- CSV reading via Arrow C GLib
- **Parquet & Feather Support**: Full native read/write for Arrow-backed files
- Dual-path operations (native + fallback)
- `explain(df)` surfaces whether a DataFrame is still on the native Arrow path (`storage_backend`, `native_path_active`)
- Supported structural rebuilds now try to stay Arrow-backed by rematerializing into a fresh native table
- **Current limitation**: unsupported builder paths (for example NA-only, to_factor, list, date, or datetime columns) still fall back to pure OCaml/T storage

✅ **Reproducibility**:

- Nix flakes for dependency management
- Deterministic execution
- Frozen syntax and semantics

### REPL

✅ **Implemented**:

- Interactive read-eval-print loop
- Multiline input support
- Persistent environment
- Auto-loading of standard library

### Testing

✅ **Implemented**:

- Unit tests (OCaml)
- Golden tests (T vs R comparison)
- Example-based tests

### Package Management & Flakes (Bug fixes)

✅ **Implemented**:

- `T_PACKAGE_PATH` flake configurations export the exact built derivations rather than raw source maps
- Packages dynamically bundle the local `src/` and `help/` directories instead of silently failing context
- `t-lang` compiler successfully stripped out of packages' default recursive `buildInputs` dependencies
- `help()` UX fallback bypasses closures gracefully by searching locally bound environment lambda variables

### Documentation

✅ **Implemented** (this release):

- README with quick start
- Getting Started guide
- Installation guide
- API Reference (all packages)
- Language Overview
- Data Manipulation Examples
- Pipeline Tutorial
- Architecture guide
- Contributing guide
- Development guide
- Comprehensive Examples
- Error Handling guide
- Reproducibility guide
- LLM Collaboration guide
- FAQ
- Troubleshooting guide
- Changelog (this file)
- **Model Interchange & PMML**: Documentation for cross-language model support and broom-style outputs for imported models.
- **Improved Data Inspection**: Enhanced `glimpse()` documentation for quick DataFrame summaries.
