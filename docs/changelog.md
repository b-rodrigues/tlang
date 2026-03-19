# Changelog

Version history and roadmap for the T programming language.

## Version 0.51.0 — First Public Release

**Status**: Alpha — Syntax and semantics frozen  
**Release Date**: February 2026

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


---

## Roadmap

### Version 0.6.0 (Beta) — Planned

**Focus**: Polyglot expansion and statistical modeling

- [ ] **Julia Support**: Native integration with Julia through a new `jn()` node type and shared Arrow memory buffers.
- [ ] **Expanded Model Interoperability**: Support for complex models from:
  - **R**: GLM, Random Forest (`randomForest`), mixed-effects models (`lme4`/`nlme`).
  - **Python**: Specialized `scikit-learn` estimators, `statsmodels` (logit/probit), and `XGBoost`.
  - **Enhanced Evaluator**: Native OCaml evaluation logic for more PMML features and model types.

### Version 1.0.0 (Stable) — Future

**Focus**: Stability and performance

- [ ] **API Freeze**: Ensuring backward compatibility for all core verbs and engine operations.
- [ ] **Extended Test Suite**: Full coverage for all edge cases in the polyglot engine and Arrow-backed compute paths.

---

## Historical Development (Pre-Alpha)

### Phase 8: Documentation & Stabilization

- Comprehensive documentation suite
- Website updates
- Alpha freeze

### Phase 7: CLI & REPL

- Interactive REPL
- Error recovery
- Standard library auto-loading

### Phase 6: LLM Tooling & Introspection

- Intent blocks
- `explain()` functions
- Pipeline introspection

### Phase 5: Math & Statistics

- Math functions
- Statistical functions with NA handling
- Linear regression

### Phase 4: Data Verbs & Window Functions

- Six core verbs (select, filter, mutate, arrange, group_by, summarize)
- All window functions (rank, offset, cumulative)
- Grouped operations

### Phase 3: Pipelines

- Pipeline syntax
- DAG execution
- Dependency resolution
- Cycle detection

### Phase 2: Tabular Data & Arrow

- Arrow C GLib integration
- DataFrame type
- CSV I/O
- Column name cleaning

### Phase 1: Language Core

- Lexer and parser
- AST and evaluator
- Basic types and operators
- Functions and closures

---

## Known Issues (Alpha 0.1)

### Performance
- **Slow for large datasets** (>1M rows): Tree-walking interpreter
- **Memory usage**: No streaming, entire datasets in RAM

### Limitations
- **No joins**: Must pre-join data externally
- **No visualization**: Export to CSV for plotting
- **Limited file formats**: CSV only
- **No user packages**: Fixed standard library

### Bugs
- **Arrow FFI edge cases**: Some Arrow operations may crash on corner cases
- **Floating-point precision**: Platform-specific differences in golden tests
- **Error messages**: Some could be more helpful

**Reporting**: Please report bugs on [GitHub Issues](https://github.com/b-rodrigues/tlang/issues)

---

## Contributing to Roadmap

We welcome input on priorities! Please:
1. Open GitHub Discussion for feature requests
2. Vote on existing feature requests
3. Contribute implementations (see [Contributing Guide](contributing.md))

---

## Versioning Policy

T follows **Semantic Versioning** (semver):

- **Major** (1.0.0): Breaking changes
- **Minor** (0.1.0): New features, backward-compatible
- **Patch** (0.1.1): Bug fixes

**Alpha/Beta status**: API may change without major version bump.

**Post-1.0**: Stable API, breaking changes only in major versions.

---

## Release Schedule

**Alpha (current)**: No fixed schedule, continuous development  
**Beta**: Expected Q3 2026  
**1.0**: Expected 2027

**Note**: Dates are estimates and may change based on development progress and community feedback.

---

**Stay Updated**: Watch the [GitHub repository](https://github.com/b-rodrigues/tlang) for release announcements!
