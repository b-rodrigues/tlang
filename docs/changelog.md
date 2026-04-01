# Changelog

## [0.51.3] - 2026-04-xx (Upcoming)

- **Lazy Pipeline Evaluation**: Implemented lazy cross-pipeline dependency resolution. 
    - Pipelines now support referencing nodes from other pipelines by name during definition without triggering immediate `NameError`.
    - Evaluation of T-runtime nodes is automatically deferred to the build phase if dependencies are unresolved, enabling intuitive and ergonomic pipeline composition.
    - The mechanism preserves all node metadata (runtime, serializers) and ensures DAG integrity for downstream compatibility checks.
- **Project Root Discovery**: Enhanced the builder's root-finding algorithm to recognize `tproject.toml` as a valid project root indicator, preventing incorrect filesystem traversal during Nix DAG generation.
- **Architectural Documentation**: Added `spec_files/eager_pipeline_evaluation.md` detailing the technical implementation and safety constraints of the new lazy evaluation engine.
- **Test Failure Summary**: Enhanced the test runner to provide a clean, aggregated summary of all failures and error messages at the end of the suite execution, improving visibility and debugging efficiency.
- **`fit_stats()` API Standardization**: Unified model-level statistics on a single, standardized `fit_stats()` function. The function now natively supports lists and dictionaries of models, allowing for effortless aggregation of goodness-of-fit statistics (R², AIC, BIC, etc.) from multiple languages (R, Python, T) into a single tidy T DataFrame.
- **Test Suite Synchronization**: Updated the internal test suite and golden benchmarks to align with the new `fit_stats()` API.
- Integration tests in b-rodrigues/t_demos now run on PRs as well.
- **ONNX Serializer Strategy**: Initial implementation of the ONNX (Open Neural Network Exchange) model interchange system.
    - Registered `^onnx` as a first-class serializer for multi-runtime model portability.
    - Added ONNX export/import helpers for R and Python in the Nix pipeline emitter.
    - Implemented T-native metadata reader (`t_read_onnx`) for orchestration and downstream evaluation in polyglot nodes.
    - Verified registry resolution and static format coherence checks for ONNX-backed artifacts.
    - *Note*: While ONNX inference is stable, the `skl2onnx` Python exporter in the current Nix environment (2026-03-29) is temporarily broken due to internal dependency issues; use real artifacts for golden tests until nixpkgs is updated.
- **PMML Decision Trees & Random Forests**: Added native PMML parsing and prediction support for tree-based models, including golden tests for `randomForest` exports.
- **PMML scikit-learn Random Forests**: Added golden coverage for `sklearn2pmml`-exported RandomForest classifier and regressor models.
- **fit_stats() for Forests**: Added tree/forest metadata (model type, number of trees, feature count, mining function) when calling `fit_stats()` on PMML random forests.
- **PMML XGBoost & LightGBM**: Added native PMML parsing and prediction support for boosted tree ensembles.
    - Added support for **LightGBM** models with shared additive tree logic.
    - Generalized the internal ensemble structure to a common `boosted_model` format.
    - Updated `fit_stats()` to provide tree counts and feature counts for all supported boosted ensembles.
    - Fixed `flake.nix` build issues for LightGBM/Boost by disabling GPU support and adjusting CMake flags for CPU-only builds.
    - Added full golden test coverage for both XGBoost and LightGBM using real artifacts from R and Python.

## Version 0.51.2 — Current Stable Release

**Status**: Beta  
**Release Date**: 28th of March 2026

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
- Null

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
- **Current limitation**: unsupported builder paths (for example null-only, factor, list, date, or datetime columns) still fall back to pure OCaml/T storage

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
