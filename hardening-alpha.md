# T Language Alpha Hardening Plan

> **Purpose**: This document outlines what needs to be completed, tested, and hardened to ensure the T Language Alpha (v0.1) is production-ready, robust, and feature-complete.

**Status**: Alpha v0.1 (February 2026) — Syntax and semantics frozen  
**Last Updated**: 2026-02-10

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State Assessment](#current-state-assessment)
3. [Test Coverage Analysis](#test-coverage-analysis)
4. [Known Issues & Gaps](#known-issues--gaps)
5. [Critical Hardening Tasks](#critical-hardening-tasks)
6. [Feature Completion Checklist](#feature-completion-checklist)
7. [Testing Requirements](#testing-requirements)
8. [Documentation Requirements](#documentation-requirements)
9. [Performance & Quality Metrics](#performance--quality-metrics)
10. [Release Readiness Criteria](#release-readiness-criteria)

---

## Executive Summary

### Alpha Release Goals

The T Language Alpha validates the core design principles:
- **Pipeline-driven workflows** with DAG execution
- **Explicit semantics** with structured errors and typed NA values
- **Data-first programming** with first-class DataFrames
- **Interactive development** via REPL and CLI
- **Reproducible analysis** with functional programming patterns

### Current Completion Status

| Category | Completion | Status |
|----------|------------|--------|
| Core Language | 95% | ✅ Strong |
| Data Manipulation | 98% | ✅ Grouped operations + window NA handling complete |
| Statistics & Math | 95% | ✅ NA parameter support complete |
| Pipeline Execution | 95% | ✅ Strong |
| Error Handling | 95% | ✅ Strong — actionable error messages with suggestions |
| Testing Infrastructure | 95% | ✅ Comprehensive NA + window function tests |
| Documentation | 95% | ✅ Strong |
| Tooling (REPL/CLI) | 95% | ✅ Strong |

**Overall Alpha Readiness**: **96%** — Strong foundation with grouped operations, NA handling, and window function hardening complete

---

## Current State Assessment

### ✅ What Works Well

#### Language Core (95% Complete)
- [x] **Arithmetic**: `+`, `-`, `*`, `/` with proper type handling
- [x] **Comparisons**: `==`, `!=`, `<`, `>`, `<=`, `>=` with type checking
- [x] **Logical Operators**: `and`, `or`, `not` with boolean semantics
- [x] **Functions**: First-class functions, closures, lambda syntax
- [x] **Pipes**: Conditional (`|>`) and unconditional (`?|>`) with error propagation
- [x] **Control Flow**: `if-else` expressions with proper scoping
- [x] **Data Structures**: Lists, named lists, dictionaries with nested support
- [x] **Variables**: Lexical scoping, shadowing, and closure capture
- [x] **Comments**: Single-line `--` comments

#### Data Manipulation (95% Complete)
- [x] **DataFrame Loading**: `read_csv()` with automatic type inference
- [x] **Schema Introspection**: `colnames()`, `nrow()`, `ncol()`
- [x] **Column Access**: Dot notation (`df.column_name`)
- [x] **Core Verbs**: `select`, `filter`, `mutate`, `arrange`, `summarize`
- [x] **Grouping**: `group_by()` with group key tracking
- [x] **Window Functions**: `row_number`, `min_rank`, `dense_rank`, `cume_dist`, `percent_rank`, `ntile`, `lag`, `lead` — with full NA support

#### Statistics & Math (90% Complete)
- [x] **Math Functions**: `sqrt`, `abs`, `log`, `exp`, `pow`
- [x] **Descriptive Stats**: `mean`, `sd`, `quantile`
- [x] **Correlation**: `cor()` for bivariate relationships
- [x] **Linear Regression**: `lm()` with formula syntax (`y ~ x`)
- [x] **Formula Interface**: First-class `Formula` type with `~` operator
- [x] **Vector Operations**: All math/stats functions support list inputs

#### Pipeline & Execution (95% Complete)
- [x] **Pipeline Definition**: `pipeline { ... }` with named nodes
- [x] **DAG Construction**: Automatic dependency resolution
- [x] **Topological Sorting**: Out-of-order node declarations supported
- [x] **Cycle Detection**: Clear error messages for circular dependencies
- [x] **Node Caching**: Memoization for expensive computations
- [x] **Pipeline Introspection**: `pipeline_nodes()`, `pipeline_deps()`, `pipeline_node()`

#### Error Handling (90% Complete)
- [x] **Structured Errors**: Symbolic error codes (TypeError, ArityError, DivisionByZero, etc.)
- [x] **Error Propagation**: Explicit error forwarding via `?|>` operator
- [x] **Error Introspection**: `is_error()`, `error_code()`, `error_message()`, `error_context()`
- [x] **Typed NA Values**: NAInt, NAFloat, NABool, NAString, NAGeneric
- [x] **NA Detection**: `is_na()` and `na()` constructors
- [x] **Assertions**: `assert()` with custom messages

#### Tooling (95% Complete)
- [x] **REPL**: Interactive shell with multi-line input support
- [x] **CLI**: `t run script.t` for script execution
- [x] **Pretty Printing**: `pretty_print()` for formatted output
- [x] **Package Management**: Standard library auto-loaded on startup
- [x] **Introspection**: `explain()`, `type()`, `length()` builtins

#### Documentation (90% Complete)
- [x] **Language Overview**: Complete reference in `docs/language_overview.md`
- [x] **Pipeline Tutorial**: Step-by-step guide in `docs/pipeline_tutorial.md`
- [x] **Data Manipulation Examples**: Cookbook in `docs/data_manipulation_examples.md`
- [x] **Formula Documentation**: Formula syntax in `docs/formulas.md`
- [x] **Specification**: Full design spec in `spec.md`
- [x] **README**: Getting started guide with Nix integration
- [x] **Examples**: 5+ worked examples in `examples/`

---

### ⚠️ What Needs Work

#### Critical Gaps (Must Fix for Alpha)

1. **~~Grouped Mutate Not Supported~~** ✅ COMPLETE
   - `group_by() |> mutate()` now passes group context to mutate expressions
   - Supports group-wise transformations (z-scores, group means, ranks within groups)

2. **~~NA Parameters Missing in Aggregations~~** ✅ COMPLETE
   - All aggregation functions (`mean`, `sum`, `sd`, `quantile`, `cor`) now support `na_rm` parameter
   - `na_rm = true` skips NA values; `na_rm = false` (default) errors on NA
   - `cor()` supports pairwise deletion with `na_rm = true`

3. **~~Window Functions with NA~~** ✅ COMPLETE
   - All ranking functions (`row_number`, `min_rank`, `dense_rank`, `cume_dist`, `percent_rank`, `ntile`) assign NA for NA positions
   - All cumulative functions (`cumsum`, `cummin`, `cummax`, `cummean`, `cumall`, `cumany`) propagate NA
   - `lag()`/`lead()` pass NA through correctly
   - Comprehensive edge case tests added (all NA, first/last NA, alternating NA)

4. **Arrow Backend Incomplete** (MEDIUM PRIORITY)
   - **Issue**: Zero-copy operations not implemented; column views stubbed out
   - **Impact**: Performance bottleneck for large datasets
   - **Test Status**: Integration tests skipped in `test_arrow_integration.ml`

#### Minor Gaps (Nice to Have)

5. **~~Error Messages Could Be More Helpful~~** ✅ COMPLETE
   - NameError now suggests similar names via Levenshtein distance: `'slect' is not defined. Did you mean 'select'?`
   - TypeError shows type conversion hints for common mismatches
   - ArityError for lambdas shows function parameter signature

6. **No Distinct/Unique Function**
   - **Issue**: Cannot remove duplicate rows from DataFrames
   - **Workaround**: Use `group_by() |> summarize()` pattern

7. **Limited File Format Support**
   - **Issue**: No support for Parquet/JSON (write_csv now available with optional sep, skip_header, skip_lines)
   - **Impact**: Parquet/JSON import/export not yet supported
   - **Roadmap**: Deferred to Beta v0.2

8. **No Join Operations**
   - **Issue**: Cannot merge DataFrames from multiple sources
   - **Roadmap**: Deferred to Beta v0.2

---

## Test Coverage Analysis

### Test Infrastructure

**Test Framework**: Custom OCaml test runner (`tests/test_runner.ml`)  
**Test Modules**: 16 test suites covering core, base, colcraft, stats, math, arrow, CLI, explain  
**Golden Tests**: R-vs-T validation on real datasets (mtcars, iris, airquality)  
**Test Execution**: `dune test` or `make golden` for full suite

### Test Statistics

| Category | Test Files | Assertions | Coverage | Status |
|----------|-----------|------------|----------|--------|
| Core Language | 10 | ~120 | 95% | ✅ Excellent |
| Base Library | 2 | ~40 | 90% | ✅ Strong |
| Data Manipulation | 4 | ~80 | 90% | ✅ Grouped ops complete |
| Math & Stats | 2 | ~70 | 95% | ✅ NA parameter support complete |
| Arrow Integration | 2 | ~15 | 60% | ⚠️ Zero-copy stubbed |
| CLI & Tooling | 1 | ~20 | 90% | ✅ Strong |
| Explain/Intent | 1 | ~30 | 95% | ✅ Excellent |
| Golden Tests | 3 | ~60 | 90% | ✅ Strong (incl. na_rm tests) |

**Total Tests**: ~625 individual assertions  
**Pass Rate**: 100% (0 failures)

### Well-Tested Features

#### Core Language
- ✅ Arithmetic with all numeric types
- ✅ Comparison operators with type checking
- ✅ Logical operators (and, or, not)
- ✅ Variable scoping and shadowing
- ✅ Function definitions and calls
- ✅ Closures and higher-order functions
- ✅ Lambda syntax
- ✅ Pipe operators (|> and ?|>)
- ✅ If-else expressions
- ✅ Lists and dictionaries
- ✅ Nested data structures

#### Data Operations
- ✅ DataFrame creation from CSV
- ✅ Column selection (`select`)
- ✅ Row filtering (`filter`)
- ✅ Column creation/transformation (`mutate`)
- ✅ Sorting (`arrange`)
- ✅ Ungrouped aggregation (`summarize`)
- ✅ Grouped aggregation (basic)
- ✅ Window functions (row_number, rank, lag, lead, etc.)

#### Error Handling
- ✅ Type errors on invalid operations
- ✅ Arity errors on wrong argument counts
- ✅ Division by zero errors
- ✅ Name errors for undefined variables
- ✅ Index out of bounds errors
- ✅ Error propagation via ?|> operator
- ✅ NA value handling

#### Pipelines
- ✅ Node dependency extraction
- ✅ Topological sorting
- ✅ Cycle detection
- ✅ Node execution order
- ✅ Caching behavior
- ✅ Error propagation in pipelines

### Undertested Features

#### High-Risk Areas (Need More Tests)

1. **Grouped Operations with Edge Cases**
   - Empty groups
   - Groups with all NA values
   - Groups with single row
   - Multiple grouping variables

2. **~~Window Functions with NA~~** ✅ COMPLETE
   - [x] `lag()`/`lead()` with NA values
   - [x] Ranking functions with ties and NA
   - [x] `ntile()` with uneven distributions

3. **Formula Interface**
   - Multi-variable formulas (`y ~ x1 + x2 + x3`)
   - Formula with transformations (`log(y) ~ sqrt(x)`)
   - Invalid formula syntax

4. **Error Recovery Patterns**
   - Deeply nested error propagation
   - Error recovery in pipelines
   - Multiple errors in sequence

5. **Large Data Scenarios**
   - DataFrames with 10,000+ rows
   - Wide DataFrames with 100+ columns
   - Memory usage under load

### Explicitly Skipped Tests

From test suite analysis, these tests are **intentionally skipped**:

```ocaml
-- In tests/arrow/test_arrow_integration.ml:
skip("Zero-copy column views not yet implemented")
skip("Owl bridge not fully integrated")

-- In tests/dataframe/test_dataframe.ml:
skip("Golden test file not found (expected but acceptable)")
```

**Count**: 2-3 explicitly skipped tests  
**Reason**: Features planned but not implemented for alpha

**Previously skipped, now resolved**:
- ~~`skip("Grouped mutate not yet supported")`~~ ✅ Implemented
- ~~`skip("mean() does not yet support na_rm parameter")`~~ ✅ Implemented
- ~~`skip("Grouped summarize with na_rm not yet supported")`~~ ✅ Implemented

---

## Known Issues & Gaps

### Critical Issues (Block Alpha Release)

#### 1. Grouped Mutate Not Implemented

**Severity**: HIGH  
**Category**: Data Manipulation  
**Impact**: Cannot perform group-wise transformations

**Description**:
#### 1. ~~Grouped Mutate Not Implemented~~ ✅ RESOLVED

**Status**: COMPLETE — `group_by() |> mutate()` now passes group sub-DataFrames to mutate lambda functions. Supports computing group means, z-scores, ranks within groups, and multiple grouping variables.

---

#### 2. ~~NA Parameter Support Missing~~ ✅ RESOLVED

**Status**: COMPLETE — All aggregation functions (`mean`, `sum`, `sd`, `quantile`, `cor`) now support the `na_rm` parameter.

- `na_rm = true` filters out NA values before computation
- `na_rm = false` (default) raises an explicit error when NA values are encountered
- `cor()` implements pairwise deletion when `na_rm = true`
- All-NA inputs return `NA(Float)` when `na_rm = true`
- Comprehensive tests and golden tests added

---

### High-Priority Issues (Should Fix for Alpha)

#### ~~3. Window Functions with NA~~ ✅ RESOLVED

**Severity**: MEDIUM  
**Category**: Data Manipulation  
**Status**: **FIXED** — All window functions now handle NA correctly

**Resolution**:
- Ranking functions (`row_number`, `min_rank`, `dense_rank`, `cume_dist`, `percent_rank`, `ntile`) assign NA for NA input positions and compute ranks only among non-NA values
- Cumulative functions (`cumsum`, `cummin`, `cummax`, `cummean`, `cumall`, `cumany`) propagate NA to all subsequent values, matching R
- `lag()`/`lead()` pass NA through correctly (already worked)

**Behavior**:
```t
lag([1.0, NA, 3.0], 1)     -- [NA, 1.0, NA]
min_rank([1.0, NA, 2.0])   -- [1, NA, 2]
cumsum([1, NA, 3])          -- [1, NA, NA]
row_number([3, NA, 1])      -- [2, NA, 1]
```

**Test Coverage**: Comprehensive — 41 new tests covering all NA edge cases

---

#### 4. Arrow Backend Incomplete

**Severity**: MEDIUM  
**Category**: Performance  
**Impact**: Performance bottleneck for large datasets (>10,000 rows)

**Description**:
The Arrow FFI integration is stubbed out. Zero-copy column views are not implemented, causing unnecessary data copying for every operation.

**Current Behavior**:
- DataFrames stored as OCaml lists of rows
- Every operation creates new list copies
- O(n) memory overhead per operation
- No vectorized operations

**Expected Performance**:
- 10,000 rows: <100ms for select/filter
- 100,000 rows: <500ms for aggregations

**Current Performance**:
- 10,000 rows: ~500ms for select/filter
- 100,000 rows: >5 seconds for aggregations

**Fix Required**:
1. Implement Arrow column views in FFI layer
2. Update DataFrame to use columnar storage
3. Implement zero-copy select/filter/arrange
4. Add vectorized operations for math/stats
5. Add benchmarks for large datasets

**Test Coverage**: Integration tests skipped in `tests/arrow/test_arrow_integration.ml`

---

### Medium-Priority Issues (Nice to Have)

#### 5. Error Messages Not Actionable

**Severity**: LOW  
**Category**: User Experience  
**Impact**: Harder to debug for new users

**Description**:
Error messages state what went wrong but don't suggest fixes.

**Examples**:
```
NameError: 'slect' is not defined
-- Could suggest: Did you mean 'select'?

TypeError: Cannot add Int and String
-- Could suggest: Try converting String to Int with int() or Int to String with string()

ArityError: Function expects 2 arguments, got 1
-- Could suggest: Missing argument at position 2
```

**Fix Required**:
1. Implement edit distance for name suggestions
2. Add type conversion suggestions to TypeError
3. Add argument hints to ArityError
4. Update error display to show suggestions

---

#### 6. No Distinct/Unique Function

**Severity**: LOW  
**Category**: Data Manipulation  
**Impact**: Verbose workaround required

**Description**:
No built-in function to remove duplicate rows.

**Workaround**:
```t
-- Current workaround:
df |> group_by(\(r) r.key) |> summarize("count", \(rows) length(rows))

-- Desired:
df |> distinct("key")
```

**Fix Required**:
1. Implement `distinct()` function
2. Support multiple column keys
3. Add tests for duplicates, all-unique, all-duplicate cases
4. Document in colcraft package

---

#### 7. No Write Operations

**Severity**: LOW  
**Category**: File I/O  
**Impact**: Parquet/JSON import/export not yet supported

**Description**:
`read_csv()` and `write_csv()` now support optional `sep`, `skip_header`, and `skip_lines` parameters. Parquet/JSON support is deferred to Beta.

**Status**: RESOLVED (write_csv implemented with optional separator)

**Roadmap**: Parquet/JSON deferred to Beta v0.2

---

#### 8. No Join Operations

**Severity**: LOW  
**Category**: Data Manipulation  
**Impact**: Cannot merge data from multiple sources

**Description**:
No `left_join()`, `inner_join()`, or other merge operations.

**Workaround**:
- Manual lookup via dictionaries
- Preprocessing in R/Python before loading

**Fix Required**:
1. Implement `left_join(df1, df2, by = "key")`
2. Support multiple join keys
3. Handle duplicate keys
4. Add tests for all join types
5. Document join semantics

**Roadmap**: Deferred to Beta v0.2

---

## Critical Hardening Tasks

### Phase 1: Complete Grouped Operations (HIGH PRIORITY)

**Goal**: Make `group_by() |> mutate()` work with group context

**Tasks**:
1. [x] **Extend DataFrame with group metadata**
   - Add `groups` field to DataFrame type
   - Store group keys and row indices
   - Implement group splitting/recombining

2. [x] **Update mutate to accept group context**
   - Detect grouped DataFrame in mutate
   - Pass group subset to lambda instead of single row
   - Aggregate results back to original row order

3. [x] **Add tests for grouped mutate**
   - [x] Test: Compute group mean
   - [x] Test: Compute z-score within groups
   - [x] Test: Rank within groups
   - [x] Test: Multiple grouping variables
   - [x] Test: Empty groups
   - [x] Test: Single-row groups

4. [x] **Document grouped mutate**
   - Add examples to `docs/data_manipulation_examples.md`
   - Update `docs/language_overview.md` with semantics
   - Add cookbook entry for common patterns

**Estimated Effort**: 8-12 hours  
**Dependencies**: None  
**Risk**: Medium (requires careful handling of group state)

---

### Phase 2: Add NA Parameter Support (HIGH PRIORITY)

**Goal**: Support `na_rm = true` in all aggregation functions

**Tasks**:
1. [x] **Implement named parameter system**
   - Extend function call AST to support named args
   - Update evaluator to handle optional parameters
   - Add default value mechanism

2. [x] **Update aggregation functions**
   - [x] `mean(data, na_rm = false)` with NA filtering
   - [x] `sum(data, na_rm = false)` with NA filtering
   - [x] `sd(data, na_rm = false)` with NA filtering
   - [x] `quantile(data, probs, na_rm = false)` with NA filtering
   - [x] `cor(x, y, na_rm = false)` with pairwise deletion

3. [x] **Add comprehensive NA tests**
   - [x] Test: All NA values (should return NA)
   - [x] Test: Some NA values with na_rm = false (should error)
   - [x] Test: Some NA values with na_rm = true (should compute)
   - [x] Test: No NA values (should work regardless of na_rm)
   - [x] Test: Grouped aggregation with NA

4. [x] **Update documentation**
   - Document na_rm parameter in function signatures
   - Add NA handling section to stats guide
   - Update examples to show NA handling patterns

**Estimated Effort**: 6-10 hours  
**Dependencies**: None  
**Risk**: Low (well-understood pattern from R)

---

### Phase 3: Harden Window Functions (MEDIUM PRIORITY) ✅ COMPLETE

**Goal**: Ensure all window functions handle NA correctly

**Tasks**:
1. [x] **Audit window function NA behavior**
   - [x] `lag()` / `lead()` — NA values pass through (already correct)
   - [x] `row_number()` — NA positions get NA rank, ranks computed among non-NA values
   - [x] `min_rank()` / `dense_rank()` — NA positions get NA rank
   - [x] `cume_dist()` / `percent_rank()` — NA positions get NA
   - [x] `ntile()` — NA positions get NA tile

2. [x] **Implement consistent NA handling**
   - NA semantics defined: ranking functions assign NA for NA positions, cumulative functions propagate NA
   - Updated all ranking functions (window_rank.ml) and cumulative functions (window_cumulative.ml)
   - Error messages are clear for non-numeric input

3. [x] **Add edge case tests**
   - [x] Test: All NA values
   - [x] Test: First/last value is NA
   - [x] Test: Alternating NA and non-NA
   - [x] Test: Empty DataFrame
   - [x] Test: Single row DataFrame

4. [x] **Document window function semantics**
   - Added Window Functions section to `docs/language_overview.md`
   - Added window function examples to `docs/data_manipulation_examples.md`
   - Updated `docs/index.html` website with window function NA semantics
   - Behavior matches R's dplyr for all window functions

**Estimated Effort**: 4-6 hours  
**Dependencies**: None  
**Risk**: Low (mostly documentation and testing)

---

### Phase 4: Improve Error Messages ✅ COMPLETE

**Goal**: Make error messages actionable with suggestions

**Tasks**:
1. [x] **Implement name suggestion system**
   - Add Levenshtein distance function
   - Find closest matching names in scope
   - Show suggestions in NameError messages

2. [x] **Add type conversion hints**
   - Detect common type mismatches
   - Suggest conversion functions
   - Show examples in error messages

3. [x] **Improve arity error messages**
   - Show expected vs actual argument count
   - Show function signature
   - Indicate which argument is missing

4. [x] **Add tests for error message quality**
   - Test: Typo in function name shows suggestion
   - Test: Type error shows conversion hint
   - Test: Arity error shows signature

**Estimated Effort**: 4-6 hours  
**Dependencies**: None  
**Risk**: Low (nice-to-have improvement)

---

### Phase 5: Add Write Operations (LOW PRIORITY)

**Goal**: Support saving DataFrames to CSV

**Tasks**:
1. [x] **Implement write_csv() function**
   - Accept DataFrame and file path
   - Support optional delimiter parameter
   - Support optional na_string parameter
   - Handle file write errors gracefully

2. [x] **Add roundtrip tests**
   - [x] Test: read_csv -> write_csv -> read_csv
   - [x] Test: Write with custom delimiter
   - [x] Test: Write with NA values
   - [x] Test: Write empty DataFrame
   - [x] Test: Write DataFrame with quoted strings

3. [x] **Document write_csv()**
   - Add to dataframe package documentation
   - Show examples of saving analysis results
   - Document parameters and error conditions

**Estimated Effort**: 3-5 hours  
**Dependencies**: None  
**Risk**: Low (straightforward implementation)  
**Roadmap**: May defer to Beta v0.2

---

## Feature Completion Checklist

### Core Language Features

#### Literals & Types
- [x] Integers (42)
- [x] Floats (3.14)
- [x] Booleans (true, false)
- [x] Strings ("hello")
- [x] NA values (NA, na_int, na_float, etc.)
- [x] Null (null)
- [x] Lists ([1, 2, 3])
- [x] Named Lists ([name: "Alice", age: 30])
- [x] Dictionaries ({key: value})

#### Operators
- [x] Arithmetic: +, -, *, /
- [x] Comparison: ==, !=, <, >, <=, >=
- [x] Logical: and, or, not
- [x] Conditional Pipe: |>
- [x] Unconditional Pipe: ?|>
- [x] Formula: ~

#### Functions & Closures
- [x] Lambda syntax: \(x) x + 1
- [x] Function keyword: function(x) x + 1
- [x] Function calls: f(x, y)
- [x] Named arguments: f(x = 1, y = 2)
- [x] Closures with captured variables
- [x] Higher-order functions (map, filter)
- [x] Recursive functions

#### Control Flow
- [x] If-else expressions
- [ ] Pattern matching (deferred to Beta)
- [ ] List comprehensions (syntax reserved, not implemented)

#### Error Handling
- [x] Structured errors (Error type)
- [x] Error codes (TypeError, NameError, etc.)
- [x] Error introspection (is_error, error_code, etc.)
- [x] Error propagation via ?|>
- [x] Typed NA values
- [x] NA detection (is_na)
- [x] Assertions (assert)

---

### Data Manipulation Features

#### DataFrame Operations
- [x] Load CSV: read_csv()
- [x] Write CSV: write_csv()
- [ ] Load Parquet (deferred to Beta)
- [ ] Load JSON (deferred to Beta)
- [x] Column selection: select()
- [x] Row filtering: filter()
- [x] Column creation: mutate()
- [x] Sorting: arrange()
- [x] Grouping: group_by()
- [x] Aggregation: summarize() (ungrouped)
- [x] Aggregation: summarize() (grouped)
- [⚠️] Grouped transformations: mutate() after group_by() (not working)
- [ ] Distinct rows: distinct() (not implemented)
- [ ] Join operations (deferred to Beta)
- [ ] Pivot operations (deferred to Beta)

#### Window Functions
- [x] row_number() — Assign row numbers
- [x] min_rank() — Ranking with ties
- [x] dense_rank() — Dense ranking
- [x] cume_dist() — Cumulative distribution
- [x] percent_rank() — Percent rank
- [x] ntile(n) — Divide into buckets
- [x] lag(offset) — Previous value
- [x] lead(offset) — Next value
- [x] All window functions with NA — Comprehensive NA handling complete

#### Schema & Introspection
- [x] colnames() — Column names
- [x] nrow() — Row count
- [x] ncol() — Column count
- [x] explain() — Structured metadata
- [x] Column access: df.column_name

---

### Math & Statistics Features

#### Math Functions
- [x] sqrt() — Square root
- [x] abs() — Absolute value
- [x] log() — Natural logarithm
- [x] exp() — Exponential
- [x] pow(base, exponent) — Power
- [ ] sin, cos, tan (not planned for alpha)
- [ ] floor, ceil, round (not planned for alpha)

#### Statistics Functions
- [x] mean() — Arithmetic mean
- [x] sd() — Standard deviation
- [x] quantile(probs) — Quantiles
- [x] cor(x, y) — Correlation
- [x] lm(formula, data) — Linear regression
- [⚠️] mean(data, na_rm) — NA parameter missing
- [⚠️] sd(data, na_rm) — NA parameter missing
- [ ] median() (use quantile(0.5))
- [ ] var() (use sd()^2)
- [ ] Distribution functions (deferred to Beta)
- [ ] Hypothesis tests (deferred to Beta)

#### Formula Interface
- [x] Formula syntax: y ~ x
- [x] Formula type (first-class)
- [x] Multi-variable formulas: y ~ x1 + x2
- [x] Formula extraction from + expressions
- [x] lm() with formula
- [ ] glm() generalized linear models (deferred)

---

### Pipeline Features

#### Pipeline Definition
- [x] pipeline { ... } syntax
- [x] Named nodes: name = expression
- [x] Out-of-order declarations
- [x] Multi-line expressions
- [x] Comments in pipelines

#### Pipeline Execution
- [x] Automatic dependency resolution
- [x] Topological sorting
- [x] Cycle detection
- [x] Error propagation
- [x] Node caching/memoization
- [x] pipeline_run(name) — Execute specific node
- [x] pipeline_node(name) — Get node value

#### Pipeline Introspection
- [x] pipeline_nodes() — List all nodes
- [x] pipeline_deps(name) — Get dependencies
- [x] explain(pipeline) — Pipeline metadata

---

### Tooling & Infrastructure

#### REPL
- [x] Interactive shell
- [x] Multi-line input
- [x] Expression evaluation
- [x] Pretty printing
- [x] Error display
- [x] History (via readline)
- [ ] Tab completion (not implemented)
- [ ] Syntax highlighting (not implemented)

#### CLI
- [x] t run script.t — Execute scripts
- [x] t repl — Start REPL
- [x] Exit codes (0 for success, 1 for error)
- [ ] t fmt (not implemented, deferred to Beta)
- [ ] t check (not implemented, deferred to Beta)

#### Build System
- [x] Dune build configuration
- [x] Nix development environment
- [x] Makefile for golden tests
- [x] Test runner (dune test)
- [x] CI integration (GitHub Actions)

#### Package System
- [x] Standard library packages
- [x] Auto-load on startup
- [x] Package registry (core, base, math, stats, etc.)
- [ ] User-defined packages (not implemented)
- [ ] Package versioning (deferred to v1.0)
- [ ] Package installation (deferred to v1.0)

---

### Intent & Explain Features

#### Intent Blocks
- [x] intent { ... } syntax
- [x] Key-value pairs
- [x] intent_fields() — Extract all fields
- [x] intent_get(key) — Get specific field
- [x] Multi-line intent blocks

#### Explain System
- [x] explain(value) — Structured introspection
- [x] explain_json(value) — JSON output
- [x] Explain for all value types
- [x] Explain for DataFrames (schema, NA stats, examples)
- [x] Explain for Pipelines (node count)
- [x] Explain for Errors (code extraction)
- [x] Explain for Functions (arity, name)

---

## Testing Requirements

### Unit Tests (Per Module)

Each feature must have corresponding tests in the test suite.

#### Core Language Tests (tests/core/)
- [x] test_arithmetic.ml — Arithmetic operations
- [x] test_comparisons.ml — Comparison operators
- [x] test_logical.ml — Logical operators
- [x] test_functions.ml — Function definitions and calls
- [x] test_pipe.ml — Pipe operators
- [x] test_ifelse.ml — Conditional expressions
- [x] test_variables.ml — Variable scoping
- [x] test_lists.ml — List operations
- [x] test_dicts.ml — Dictionary operations
- [x] test_semantics.ml — Core semantics edge cases

#### Base Library Tests (tests/base/)
- [x] test_na.ml — NA value handling
- [x] test_errors.ml — Error handling and propagation

#### Data Manipulation Tests (tests/colcraft/)
- [x] test_colcraft.ml — DataFrame verbs (select, filter, mutate, etc.)
- [⚠️] Test grouped mutate (currently skipped)
- [⚠️] Test NA parameter in aggregations (currently skipped)
- [x] test_window.ml — Window functions

#### Math & Statistics Tests (tests/stats/, tests/math/)
- [x] test_math.ml — Math functions
- [x] test_stats.ml — Statistics functions
- [⚠️] Test na_rm parameter (currently skipped)

#### Pipeline Tests (tests/pipeline/)
- [x] Basic pipeline execution
- [x] Dependency resolution
- [x] Cycle detection
- [x] Node caching
- [x] Error propagation

#### Infrastructure Tests
- [x] test_cli.ml — CLI integration
- [x] test_explain_tests.ml — Explain system
- [x] test_dataframe.ml — DataFrame operations

#### Arrow Integration Tests (tests/arrow/)
- [x] test_arrow_integration.ml (some tests skipped)
- [x] test_owl_bridge.ml (integration incomplete)

---

### Golden Tests (tests/golden/)

**Purpose**: Validate T output against R reference implementations

**Datasets**: mtcars, iris, airquality (generated from R)

**Test Categories**:
- [x] Data loading (read_csv)
- [x] Column selection (select)
- [x] Row filtering (filter)
- [x] Column transformation (mutate)
- [x] Sorting (arrange)
- [x] Ungrouped aggregation (summarize)
- [x] Grouped aggregation (group_by |> summarize)
- [x] Window functions (lag, lead, rank, etc.)
- [x] Statistics (mean, sd, cor, lm)

**Test Framework**: R testthat comparing CSV outputs

**Execution**: `make golden` or `make golden-quick`

**Coverage**: ~40 golden tests across data operations

---

### Edge Case Tests (To Add)

#### Empty Data Structures
- [ ] Empty DataFrame (0 rows)
- [ ] Empty list
- [ ] Empty dict
- [ ] Empty string

#### Single-Element Structures
- [ ] DataFrame with 1 row
- [ ] List with 1 element
- [ ] Dict with 1 key

#### Large Data
- [ ] DataFrame with 10,000 rows
- [ ] DataFrame with 100 columns
- [ ] Deeply nested lists (10+ levels)
- [ ] Large string (>1MB)

#### NA Edge Cases
- [ ] All NA values in column
- [ ] Alternating NA and non-NA
- [ ] NA in grouping variables
- [ ] NA in sorting key
- [ ] NA in join key

#### Error Edge Cases
- [ ] Deeply nested error propagation (10+ levels)
- [ ] Error in pipeline node dependency
- [ ] Error in grouped operation
- [ ] Division by zero in DataFrame column

#### Type Edge Cases
- [ ] Mixed types in list (heterogeneous)
- [ ] Numeric string vs actual number
- [ ] Boolean coercion edge cases
- [ ] Float precision limits

---

### Performance Tests (To Add)

#### Benchmarks
- [ ] read_csv() on 10K, 100K, 1M rows
- [ ] select/filter on large DataFrames
- [ ] group_by |> summarize on many groups
- [ ] Pipeline with 100 nodes
- [ ] Recursive function (depth 1000)

#### Memory Tests
- [ ] DataFrame memory footprint
- [ ] Pipeline caching memory usage
- [ ] Closure capture memory leaks
- [ ] Long-running REPL session

---

## Documentation Requirements

### User-Facing Documentation

#### Completed Documentation
- [x] README.md — Quick start and overview
- [x] docs/language_overview.md — Complete language reference
- [x] docs/pipeline_tutorial.md — Step-by-step pipeline guide
- [x] docs/data_manipulation_examples.md — Practical cookbook
- [x] docs/formulas.md — Formula syntax and usage
- [x] ALPHA.md — Alpha release notes
- [x] ROADMAP.md — Future development plans
- [x] CHANGELOG.md — Version history
- [x] spec.md — Full language specification

#### Documentation Gaps
- [ ] NA handling guide (comprehensive)
- [ ] Error recovery patterns (best practices)
- [ ] Performance tuning guide
- [ ] Migration from R guide
- [ ] API reference (auto-generated)
- [ ] Tutorial videos (optional)

---

### Code Documentation

#### Completed Code Documentation
- [x] AST type definitions (ast.ml)
- [x] Parser grammar (parser.mly)
- [x] Lexer tokens (lexer.mll)
- [x] Evaluator logic (eval.ml)

#### Code Documentation Gaps
- [ ] Function-level comments in eval.ml
- [ ] Type annotations in complex functions
- [ ] Design rationale comments
- [ ] Performance notes for critical paths

---

### Example Code

#### Completed Examples
- [x] examples/ci_test.t — Comprehensive integration test
- [x] examples/data_analysis.t — End-to-end data analysis
- [x] examples/pipeline_example.t — Pipeline features
- [x] examples/statistics_example.t — Math and statistics
- [x] examples/error_recovery.t — Error recovery with ?|>

#### Missing Examples
- [ ] Grouped operations example (after fixing grouped mutate)
- [ ] NA handling example
- [ ] Large dataset example (10K+ rows)
- [ ] Multi-file analysis (after implementing joins)
- [ ] Time series analysis (using window functions)

---

## Performance & Quality Metrics

### Performance Targets (Alpha)

**Small Data (< 1,000 rows)**
- [x] read_csv(): < 100ms
- [x] select/filter: < 50ms
- [x] mutate: < 50ms
- [x] arrange: < 100ms
- [x] group_by |> summarize: < 100ms

**Medium Data (1,000 - 10,000 rows)**
- [ ] read_csv(): < 500ms (not tested)
- [ ] select/filter: < 200ms (not tested)
- [ ] mutate: < 200ms (not tested)
- [ ] arrange: < 500ms (not tested)
- [ ] group_by |> summarize: < 500ms (not tested)

**Large Data (10,000+ rows)**
- [ ] read_csv(): < 2s (not tested)
- [ ] select/filter: < 1s (not tested)
- [ ] mutate: < 1s (not tested)
- [ ] arrange: < 2s (not tested)
- [ ] group_by |> summarize: < 2s (not tested)

**Note**: Performance targets are aspirational. Tree-walking interpreter will be slow on large data. Arrow backend and bytecode compiler planned for v1.0.

---

### Code Quality Metrics

#### Test Coverage
- **Target**: >90% line coverage
- **Current**: ~85% (estimated)
- **Gap**: Window functions, error edge cases, large data

#### Documentation Coverage
- **Target**: All public functions documented
- **Current**: ~80%
- **Gap**: Some stdlib functions lack usage examples

#### Error Handling
- **Target**: No uncaught exceptions in user code
- **Current**: ~95%
- **Gap**: Some edge cases may panic instead of returning Error

#### Type Safety
- **Target**: No runtime type errors on well-typed code
- **Current**: ~90%
- **Gap**: Some operations have implicit type assumptions

---

### Build & CI Metrics

#### Build Time
- **Target**: < 30 seconds for full build
- **Current**: ~20 seconds (Dune + OCaml)
- **Status**: ✅ Meeting target

#### Test Time
- **Target**: < 60 seconds for full test suite
- **Current**: ~45 seconds (unit + golden tests)
- **Status**: ✅ Meeting target

#### CI Pipeline
- [x] Automated builds on push
- [x] Automated tests on PR
- [x] Nix flake checks
- [ ] Performance regression tests (not implemented)
- [ ] Code coverage reporting (not implemented)

---

## Release Readiness Criteria

### Must-Have for Alpha Release

#### Critical Features (100% Required)
- [ ] **Fix grouped mutate** — group_by() |> mutate() must work
- [ ] **Add na_rm parameter** — mean(), sd(), sum() must support NA handling
- [ ] **Harden window functions** — All window functions handle NA correctly
- [ ] **Documentation for critical features** — Grouped operations and NA handling documented
- [ ] **Tests for critical features** — No skipped tests for core functionality

#### Core Stability (100% Required)
- [x] REPL does not crash on user input
- [x] CLI handles file errors gracefully
- [x] Parser rejects invalid syntax with clear messages
- [x] All non-skipped tests pass
- [x] No memory leaks in core operations
- [x] Error messages are understandable

#### Documentation (100% Required)
- [x] README with quick start
- [x] Language overview with all syntax
- [x] Examples for all core features
- [ ] NA handling guide (need to add)
- [ ] Grouped operations examples (need to add after fix)

---

### Nice-to-Have for Alpha Release

#### Enhanced Features (Optional)
- [x] write_csv() for saving results
- [ ] distinct() for removing duplicates
- [ ] Better error messages with suggestions
- [ ] Performance optimizations

#### Enhanced Documentation (Optional)
- [ ] Video tutorials
- [ ] Migration from R guide
- [ ] Performance tuning guide
- [ ] Auto-generated API reference

#### Enhanced Testing (Optional)
- [ ] Performance benchmarks
- [ ] Code coverage reporting
- [ ] Fuzz testing
- [ ] Property-based testing

---

### Beta Release Criteria (Future)

To move from Alpha (v0.1) to Beta (v0.2), the following must be completed:

#### Language Features
- [ ] Pattern matching (match expressions)
- [ ] List comprehensions
- [ ] Lenses (immutable updates)
- [ ] String interpolation

#### Data Features
- [ ] Parquet/JSON file support
- [ ] write_parquet()
- [ ] Join operations (left_join, inner_join, etc.)
- [ ] Pivot operations (pivot_wider, pivot_longer)

#### Statistics
- [ ] Distribution functions (rnorm, dnorm, etc.)
- [ ] Hypothesis testing (t_test, chi_squared)
- [ ] Multiple regression with summary

#### Tooling
- [ ] VS Code syntax highlighting
- [ ] Language server (LSP)
- [ ] Code formatter (t fmt)
- [ ] Debugger for pipelines

#### Performance
- [ ] Complete Arrow backend integration
- [ ] Zero-copy operations
- [ ] Benchmark suite

---

## Appendix: Test File Inventory

### Test Files by Category

#### Core Language (10 files)
1. `tests/core/test_arithmetic.ml` — Arithmetic operations
2. `tests/core/test_comparisons.ml` — Comparison operators
3. `tests/core/test_logical.ml` — Logical operators
4. `tests/core/test_functions.ml` — Function definitions
5. `tests/core/test_pipe.ml` — Pipe operators
6. `tests/core/test_ifelse.ml` — Conditional expressions
7. `tests/core/test_variables.ml` — Variable scoping
8. `tests/core/test_lists.ml` — List operations
9. `tests/core/test_dicts.ml` — Dictionary operations
10. `tests/core/test_semantics.ml` — Edge cases

#### Base Library (2 files)
11. `tests/base/test_na.ml` — NA values
12. `tests/base/test_errors.ml` — Error handling

#### Data Manipulation (4 files)
13. `tests/colcraft/test_colcraft.ml` — DataFrame verbs
14. `tests/colcraft/test_window.ml` — Window functions
15. `tests/dataframe/test_dataframe.ml` — DataFrame ops
16. `tests/pipeline/test_pipeline.ml` — Pipeline execution

#### Math & Statistics (2 files)
17. `tests/math/test_math.ml` — Math functions
18. `tests/stats/test_stats.ml` — Statistics

#### Infrastructure (3 files)
19. `tests/cli/test_cli.ml` — CLI integration
20. `tests/explain/test_explain_tests.ml` — Explain system
21. `tests/test_runner.ml` — Test orchestrator

#### Arrow Integration (2 files)
22. `tests/arrow/test_arrow_integration.ml` — Arrow FFI
23. `tests/arrow/test_owl_bridge.ml` — Owl bridge

#### Golden Tests (3 R scripts + 1 shell script)
24. `tests/golden/generate_expected.R` — Generate R reference
25. `tests/golden/generate_expected_stats.R` — Generate stats reference
26. `tests/golden/generate_expected_window.R` — Generate window reference
27. `tests/golden/test_golden_r.R` — Compare T vs R outputs
28. `tests/golden/run_all_t_tests.sh` — Execute T test scripts

---

## Appendix: Known Technical Debt

### High-Priority Technical Debt

1. **Tree-Walking Interpreter Performance**
   - **Issue**: O(n) list operations, no vectorization
   - **Impact**: Slow on large data (>10K rows)
   - **Fix**: Bytecode compiler + Arrow backend (v1.0)

2. **No Type System**
   - **Issue**: Runtime type errors on invalid operations
   - **Impact**: Errors discovered late, harder to debug
   - **Fix**: Type inference system (v1.0)

3. **Manual Memory Management in FFI**
   - **Issue**: C bindings require manual free()
   - **Impact**: Potential memory leaks
   - **Fix**: Smart pointers or reference counting (v1.0)

### Medium-Priority Technical Debt

4. **No Lazy Evaluation**
   - **Issue**: All expressions evaluated eagerly
   - **Impact**: Unnecessary computation in pipelines
   - **Fix**: Lazy evaluation for DataFrames (v1.0)

5. **String Representation is Verbose**
   - **Issue**: No string interpolation, manual concatenation
   - **Impact**: Harder to format output
   - **Fix**: String interpolation (Beta v0.2)

6. **No Module System**
   - **Issue**: All code in global namespace
   - **Impact**: Name collisions, no encapsulation
   - **Fix**: Module system (v1.0)

### Low-Priority Technical Debt

7. **Test Framework is Custom**
   - **Issue**: Not using standard OCaml test library (Alcotest)
   - **Impact**: Harder to integrate with ecosystem tools
   - **Fix**: Migrate to Alcotest (optional)

8. **No Continuous Benchmarking**
   - **Issue**: Performance regressions not detected
   - **Impact**: May introduce slow operations unknowingly
   - **Fix**: Add CI benchmarks (optional)

---

## Conclusion

The T Language Alpha (v0.1) is **88% complete** with a strong foundation in core language features, data manipulation, and pipeline execution. To achieve full alpha readiness, the following **critical tasks** must be completed:

1. **Fix grouped mutate** (8-12 hours) — HIGH PRIORITY
2. **Add na_rm parameter** (6-10 hours) — HIGH PRIORITY
3. **Harden window functions** (4-6 hours) — MEDIUM PRIORITY
4. **Document critical features** (2-4 hours) — HIGH PRIORITY

After completing these tasks, the alpha release will be **robust, feature-complete, and ready for user testing**.

**Estimated total effort**: 20-32 hours of focused development work.

---

**Next Steps**:
1. Create GitHub issues for critical hardening tasks
2. Prioritize grouped mutate and na_rm parameter
3. Set target dates for alpha hardening completion
4. Schedule final testing and validation phase

**Contact**: For questions or feedback on this hardening plan, open an issue on GitHub: https://github.com/b-rodrigues/tlang/issues
