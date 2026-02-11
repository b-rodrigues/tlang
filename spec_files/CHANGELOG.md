# Changelog

All notable changes to the T programming language are documented here.

## [Alpha 0.1] — 2026-02

### Actionable Error Messages
- Levenshtein-based name suggestions for NameError: `'prnt' is not defined. Did you mean 'print'?`
- Type conversion hints for TypeError: common mismatches suggest corrective actions
- Function signature display in ArityError for lambdas: `Expected 2 arguments (a, b) but got 1`

### Formula Interface
- R-style formula syntax with `~` operator: `y ~ x`, `mpg ~ hp + wt`
- `Formula` type: formulas are first-class values (`type(y ~ x)` → `"Formula"`)
- Named arguments for function calls using `=` syntax: `lm(data = df, formula = y ~ x)`
- `lm()` refactored to use formula interface instead of positional string arguments
- `lm()` result now includes the formula object alongside coefficients and statistics
- Multi-variable formula support: `y ~ x1 + x2 + x3`
- Formula variable extraction from `+` expressions

### Maybe-Pipe Operator
- `?|>` unconditional pipe operator: always forwards the left-hand value (including errors) to the right-hand function
- Enables explicit error recovery patterns (Railway-Oriented Programming)
- Both `|>` and `?|>` share the same precedence and left-associativity
- Multi-line continuation support: `\n  ?|>` works like `\n  |>`

### Phase 0 — Foundations
- OCaml project structure with Dune build system
- Lexer (OCamllex) and parser (Menhir)
- AST definition with expression types
- Tree-walking evaluator
- Basic REPL

### Phase 1 — Values, Types, and Errors
- Unified runtime value representation (Int, Float, Bool, String, List, Dict)
- Explicit NA values with type tags (NABool, NAInt, NAFloat, NAString, NAGeneric)
- No implicit NA propagation — operations on NA produce errors
- Structured error system with symbolic codes (TypeError, ArityError, DivisionByZero, etc.)
- Error values instead of exceptions for user-visible errors
- `assert()` with custom messages and NA handling
- `error()`, `is_error()`, `error_code()`, `error_message()`, `error_context()`

### Phase 2 — Tabular Data
- DataFrame type with columns, rows, and schema
- `read_csv()` with type inference (Int, Float, Bool, String, NA)
- `colnames()`, `nrow()`, `ncol()`
- Column access via dot notation (`df.age`)
- DataFrame immutability at the language level

### Phase 3 — Pipelines and Execution Graph
- `pipeline { ... }` construct with named nodes
- DAG-based dependency resolution with topological sort
- Out-of-order node declarations
- Cycle detection with clear error messages
- Node-level caching
- `pipeline_nodes()`, `pipeline_deps()`, `pipeline_node()`, `pipeline_run()`
- Error propagation in pipeline nodes

### Phase 4 — Core Data Verbs
- `select()` — column selection by name
- `filter()` — row filtering with predicate functions
- `mutate()` — column addition and transformation
- `arrange()` — sorting (ascending and descending)
- `group_by()` — grouping with group key tracking
- `summarize()` — aggregation (ungrouped and grouped)

### Phase 5 — Numerical and Statistical Libraries
- `math` package: `sqrt()`, `abs()`, `log()`, `exp()`, `pow()`
- `stats` package: `mean()`, `sd()`, `quantile()`, `cor()`, `lm()`
- Vector operations for all math functions
- Explicit NA handling in all math/stats functions
- Linear regression with slope, intercept, R², and observation count
- All functions auto-loaded at startup

### Phase 6 — Intent Blocks and Tooling Hooks
- `intent { ... }` block syntax for structured metadata
- `intent_fields()` — extract all fields as Dict
- `intent_get()` — access specific field
- `explain()` — structured introspection for all value types
- DataFrame explain with schema, NA stats, and example rows
- Pipeline explain with node count
- Error explain with code extraction

### Phase 7 — REPL, CLI, and Packaging
- `t repl` — interactive REPL with multi-line input
- `t run file.t` — script execution from CLI
- `pretty_print()` builtin for formatted output
- `packages()` — list loaded packages
- `package_info()` — detailed package information
- Standard package registry: core, base, math, stats, dataframe, colcraft, pipeline, explain
- All packages loaded automatically at startup

### Phase 8 — Stabilization and Alpha Release
- Language overview documentation
- Pipeline tutorial with worked examples
- Data manipulation examples and cookbook
- Golden tests for pipeline baselines
- Additional core semantic unit tests
- End-to-end example analyses (data analysis, pipelines, statistics)
- Alpha release notes with frozen syntax
- Roadmap for beta and v1.0

### CSV I/O Enhancements
- `read_csv()` now supports optional `separator` parameter for custom delimiters (e.g., `separator = ";"`)
- `read_csv()` now supports optional `skip_lines` parameter to skip leading lines (e.g., comments)
- `read_csv()` now supports optional `skip_header` parameter for headerless CSV files (columns named V1, V2, ...)
- `write_csv()` now supports optional `separator` parameter for custom delimiters
- Roundtrip tests: read_csv → write_csv → read_csv with default and custom separators
- Tests for writing empty DataFrames and DataFrames with NA values
