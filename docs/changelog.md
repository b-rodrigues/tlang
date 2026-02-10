# Changelog

Version history and roadmap for the T programming language.

## Version 0.1.0 (Alpha) — Current Release

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
- `read_csv` (with `sep`, `skip_lines`, `skip_header`, `clean_colnames`)
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

✅ **Intent Blocks**:
- Structured metadata for LLM collaboration
- Document assumptions, constraints, goals
- Machine-readable format

✅ **Arrow Integration**:
- Zero-copy columnar storage
- CSV reading via Arrow C GLib
- Dual-path operations (native + fallback)

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

---

## Roadmap

### Version 0.2.0 (Beta) — Planned

**Focus**: Performance and expanded functionality

#### Performance Improvements
- [ ] Bytecode compilation (replace tree-walking)
- [ ] Stack-based VM
- [ ] Lazy evaluation for pipelines
- [ ] More Arrow compute kernels

#### New Features
- [ ] DataFrame joins (`join`, `left_join`, `inner_join`)
- [ ] More statistical functions (`t_test`, `anova`, `chisq_test`)
- [ ] Multiple regression (`lm(y ~ x1 + x2 + x3)`)
- [ ] Parquet support
- [ ] Basic plotting (via Arrow/matplotlib integration)

#### Language Enhancements
- [ ] Pattern matching on values
- [ ] Recursive functions optimization (tail-call)
- [ ] Anonymous pipeline blocks
- [ ] Destructuring assignment

#### Standard Library
- [ ] String manipulation package (`split`, `join`, `regex`)
- [ ] Date/time package (`parse_date`, `diff_days`)
- [ ] File I/O package (`read_lines`, `write_lines`)

### Version 0.3.0 (Beta) — Planned

**Focus**: Ecosystem and tooling

#### Tooling
- [ ] Language Server Protocol (LSP) for IDE support
- [ ] Formatter (`t-fmt`)
- [ ] Linter (`t-lint`)
- [ ] Package manager (`t-pkg`)

#### Ecosystem
- [ ] User-contributed packages
- [ ] Package registry
- [ ] Binary distribution (no source build)

#### Language Features
- [ ] Optional static typing (gradual typing)
- [ ] Type annotations and inference
- [ ] Modules and namespaces

### Version 1.0.0 (Stable) — Future

**Focus**: Production-ready, stable API

#### Stability
- [ ] API freeze (no breaking changes)
- [ ] Comprehensive benchmarks
- [ ] Performance parity with Pandas/dplyr
- [ ] 95%+ test coverage

#### Features
- [ ] Distributed execution (multi-node pipelines)
- [ ] GPU acceleration (Arrow Compute on CUDA)
- [ ] Database integration (SQL, DuckDB)
- [ ] Streaming data support

#### Documentation
- [ ] Books and tutorials
- [ ] Video courses
- [ ] Case studies
- [ ] Certification program

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
