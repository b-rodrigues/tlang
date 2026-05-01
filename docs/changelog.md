# Changelog

## [0.51.x] - 2026-05-xx

**Status**: Beta  

### Quality & Test Coverage
- **Expanded Stats Package Coverage**:
    - Added comprehensive golden tests for 15+ specialized statistical functions, probability distributions, and transformations.
    - **Specialized Metrics**: Verified `cv`, `fivenum`, `trimmed_mean`, `mad`, `iqr`, `range`, `var`, and `cov` against R baselines.
    - **Advanced Moments**: Added coverage for `skewness` and `kurtosis` (excess kurtosis) using population-moment calculations.
    - **Probabilistic Distributions**: Added golden tests for `pnorm` (standard normal approximation), `pt`, `pf`, and `pchisq` CDFs.
    - **Statistical Operations**: Verified `winsorize`, `huber_loss`, `normalize`, and Pearson `cor` against R reference values.
    - **Data Transformations**: Added a golden test for `standardize` and `scale` using `iris$Sepal.Length`.
    - **Model Accessors**: Added regression tests for `coef`, `conf_int`, `sigma`, `nobs`, and `df_residual` for linear models.
- **Critical Fixes**:
    - **Quantile Accuracy**: Fixed a critical bug in the C-based quantile implementations (`normal_quantile`, `t_quantile`) where tail approximations were incorrect, leading to broken confidence intervals. Implemented high-precision Acklam's algorithm for normal quantiles and accurate Cornish-Fisher expansion for $t$ quantiles.
- **Improved Base Package Coverage**:
    - Significantly increased test coverage for `base` package builtins, specifically targeting error handling, NA container logic, and serialization.
    - **NA Mapping**: Verified `is_na` vectorization across Vectors and named Lists.
    - **Serialization Robustness**: Added comprehensive error-path testing for `serialize`, `deserialize`, `t_write_json`, and `t_read_json`, including type-mismatch and file-system failure scenarios.
- **Improved Core Package Coverage**:
    - Expanded test coverage for `core` package builtins, including `args`, `help`, `apropos`, and `write_text`.
    - **Introspection**: Added tests for the `args()` builtin on both builtins and lambdas, ensuring correct parameter name and type extraction.
    - **Coverage Integration**: Added the new colcraft coverage tests to the test runner so these scenarios are exercised in regular test execution.
    - **Colcraft Coverage**: Expanded testing for `fill`, `replace_na`, `complete`, `relocate`, `count`, `slice`, `unnest`, `separate`, and `uncount`. Verified `downup` direction logic and regex error handling.
    - **Pretty Printing**: Verified nested collection and visual metadata (Altair) rendering in `pretty_print`.
    - **Help System**: Added regression coverage for invalid input types and missing-documentation cases in `help()` and `apropos()`.
- **Enhanced Arity Error Reporting**:
    - Updated the core evaluator to include function names in arity error messages for all builtins (e.g., `Function `length` expects...`).
    - Standardized arity error expectations across the entire test suite (1944/1944 tests passing).

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
- **Unified `get()` and New `sym()` Builtin**:
    - Added the `sym()` core builtin for programmatic symbol creation.
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
    - Supports automatic rendering of R (`ggplot2`) and Python (Matplotlib, Seaborn, Plotly, Altair, Plotnine) plots within the Nix sandbox.
    - Implemented headless rendering for interactive libraries: Plotly (via `kaleido`) and Altair (via `vl-convert`).
    - **Dependency Automation**: `tlang` now automatically suggests or injects `cloudpickle` when plotting libraries are detected in Python nodes to ensure reliable serialization of complex objects containing lambdas.
- **Transparent `read_node()` for Plots**:
    - `read_node()` now recognizes nodes of class `ggplot`, `matplotlib`, `plotnine`, `seaborn`, `plotly`, or `altair`.
    - Instead of returning an opaque binary artifact, it returns a structured JSON-backed dictionary of the plot's metadata, enabling programmatic verification of visualizations in T scripts.

### Serializable Lens Architecture
- **Refactored Lens Implementation**:
    - Replaced functional closure-based lenses with a structured `VLens` sum type.
    - **Nix-Isolated Persistence**: Lenses can now be serialized to disk and passed between separate Nix-build pipeline nodes without losing their state or functionality.
    - **Unified `get()` Integration**: The `get()` builtin now natively supports `VLens` for data focus, providing a single, consistent interface for variable lookup, indexing, and lens-based retrieval.

### Core Evaluator, Emitter & Documentation Refinements
- **Improved Docstring Coverage**: Added full T-style documentation (descriptions, parameters, examples) for `get()`, `sym()`, and related primitives.
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
    - **`dataframe()` Constructor**: Added support for Dictionary-based construction and automatic scalar recycling.
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
- List comprehensions
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
- **Current limitation**: unsupported builder paths (for example NA-only, factor, list, date, or datetime columns) still fall back to pure OCaml/T storage

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
