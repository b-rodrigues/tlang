# Arrow: current status and next steps

This document summarizes the current Apache Arrow-related state of the repository across `docs/`, `src/`, `tests/`, and `spec_files/`.

It is meant to answer four questions:

1. What Arrow-related code and documentation already exist?
2. What is currently implemented vs. still missing?
3. What do the current tests cover?
4. What tests and documentation should be added next?

## Executive summary

The repository already has a substantial Arrow backend:

- a dedicated Arrow implementation under `src/arrow/`,
- a large C FFI layer in `src/ffi/arrow_stubs.c`,
- Arrow IPC read/write builtins (`read_arrow`, `write_arrow`),
- pipeline-level Arrow serialization/deserialization support,
- dedicated Arrow integration and performance tests,
- and multiple planning/hardening documents in `spec_files/`.

The most important caveat is that the repository currently mixes **current-state docs** and **historical planning docs**:

- some newer files reflect the real backend well,
- while some older planning/spec documents still describe Arrow as mostly unimplemented or stubbed.

There is also still an important CSV-path distinction to document clearly:

- `src/arrow/arrow_io.ml` contains a native Arrow CSV reader,
- and the public `read_csv` builtin in `src/packages/dataframe/t_read_csv.ml` now delegates to `Arrow_io.read_csv` when callers use the default CSV options.
- non-default parsing behaviors such as custom separators, header skipping, line skipping, and column-name cleaning still use the OCaml parser path.
- this is now a documented split between the fast native default path and the richer compatibility path, rather than an entirely missing integration.

So Arrow support is real and broad, but not yet fully unified or fully documented from a user point of view.

## What exists today

### Documentation in `docs/`

The existing documentation mentions Arrow in several places, and `docs/arrow-current-status-next-steps.md` now serves as the dedicated Arrow overview/status page.

Relevant files:

- `docs/architecture.md`
  - describes Arrow as the DataFrame backend and mentions zero-copy access and vectorized compute.
- `docs/installation.md`
  - explains that the Nix environment builds Apache Arrow and related dependencies.
- `docs/troubleshooting.md`
  - includes Arrow-specific setup and debugging notes such as `arrow-glib` availability and native-code crash guidance.
- `docs/performance.md`
  - is currently the closest thing to an Arrow backend overview.
  - explains native vs fallback execution paths, zero-copy numeric views, grouping, and performance expectations.

Current documentation strengths:

- readers can tell that Arrow exists and is important,
- installation and troubleshooting mention Arrow dependencies,
- performance docs explain the native/fallback split.

Current documentation gaps:

- the generated reference docs for `read_arrow` / `write_arrow` exist, but there is still no broader user-facing Arrow I/O guide,
- there is still no concise support matrix explaining which Arrow types are fully supported, partially supported, or still fallback-only,
- the status page exists, but the rest of the docs do not yet surface it as the central Arrow landing page,
- there is still no short docs-facing summary of what the Arrow tests cover.

### Source code in `src/`

#### Core backend

The dedicated Arrow implementation lives in:

- `src/arrow/arrow_table.ml`
- `src/arrow/arrow_compute.ml`
- `src/arrow/arrow_io.ml`
- `src/arrow/arrow_ffi.ml`
- `src/arrow/arrow_bridge.ml`
- `src/arrow/arrow_column.ml`
- `src/arrow/arrow_owl_bridge.ml`
- `src/ffi/arrow_stubs.c`

Taken together, these files provide:

- Arrow-backed table representation with optional native handle,
- pure-OCaml fallback tables,
- schema/type mapping,
- native materialization when supported,
- Arrow compute wrappers for projection, filtering, sorting, scalar arithmetic, math, aggregation, comparisons, and grouping,
- Arrow IPC read/write,
- native list-column and dictionary-column support,
- date support,
- NA-only native materialization support,
- zero-copy numeric column views via Bigarray,
- conversion between Arrow storage and T runtime values,
- bridge utilities for statistical work via `Arrow_owl_bridge`.

#### User-facing and integration entry points

Arrow also shows up outside `src/arrow/`:

- `src/packages/dataframe/t_read_arrow.ml`
  - exposes Arrow IPC reading to T as `read_arrow`.
- `src/packages/dataframe/t_write_arrow.ml`
  - exposes Arrow IPC writing to T as `write_arrow`.
- `src/packages/dataframe/t_dataframe.ml`
  - `dataframe`, `pull`, and `to_array` all interact with Arrow-backed tables and Arrow-derived column types.
- `src/packages/dataframe/t_read_csv.ml`
  - creates Arrow-backed DataFrames and uses `Arrow_io.read_csv` for the default public CSV path, while routing non-default parsing options through the OCaml parser plus `Arrow_bridge`.
- `src/pipeline/builder_read_node.ml` and `src/packages/pipeline/read_node.ml`
  - use Arrow IPC reading in pipeline flows.
- `src/pipeline/nix_emit_node.ml`
  - emits Arrow helpers for R/Python pipeline nodes and wires Arrow serializer/deserializer behavior into generated node code.
- `src/dune`
  - builds and links the Arrow C stubs through `arrow-glib`.

## What is currently implemented

### Clearly implemented today

Based on the code currently in the repository, the following are present:

- Arrow-backed tables with GC-managed native handles
- native/fallback dual-path execution
- schema extraction and column access
- project/select
- filter
- sort/arrange
- add/replace column behavior
- scalar arithmetic (`add`, `subtract`, `multiply`, `divide`)
- unary math (`sqrt`, `abs`, `log`, `exp`, `pow`)
- column aggregations (`sum`, `mean`, `min`, `max`)
- scalar comparisons
- group-by plus group aggregations (`sum`, `mean`, `count`)
- Arrow IPC read/write
- dictionary/factor columns
- list columns with nested DataFrame reconstruction
- date columns
- NA-only columns
- zero-copy views for native numeric columns
- Arrow-to-Owl bridge for numeric/statistical workflows
- serialization hardening for native-backed DataFrames crossing process boundaries
- runtime disable switch via `TLANG_DISABLE_ARROW`

### Implemented, but not consistently surfaced

These features exist in the backend, but are not yet cleanly represented in user-facing docs or entry points:

- Arrow IPC support is implemented, but under-documented.
- Pipeline Arrow interop exists, but most of the narrative lives in `spec_files/` and tests rather than in `docs/`.
- Native Arrow CSV reading exists in `src/arrow/arrow_io.ml`, and the public `read_csv()` builtin uses it for the default CSV path.
- `docs/performance.md` still describes dictionary/factor, list, and date columns as unsupported for native rebuild even though the code now includes native dictionary, list, and date materialization paths.

### Partially implemented or still limited

The code also shows some areas that are either incomplete or intentionally constrained:

- **Datetime native materialization**
  - `Arrow_table.DatetimeColumn` exists and `Arrow_io.build_column` can parse timestamps,
  - but `Arrow_table.is_arrow_table_new_supported` still rejects `DatetimeColumn`,
  - and the Arrow type-tag mapping does not currently expose a dedicated timestamp tag in the same way it does for date/dictionary/list.
- **List columns**
  - native support exists, but only for list-of-struct shapes whose sub-fields are primitive supported types and whose nested tables share a schema.
- **CSV path consistency**
  - there are effectively two Arrow-related CSV stories:
    - backend-native `Arrow_io.read_csv`,
    - user-facing `read_csv` in `t_read_csv.ml`.
  - These should eventually converge.

## What appears to be missing

### Missing or underdeveloped user-facing documentation

- A single Arrow overview/status page in `docs/`
- User docs for `read_arrow` and `write_arrow`
- Documentation for Arrow-backed pipeline interchange as a supported workflow
- Clear support matrix for:
  - primitive columns,
  - date/datetime,
  - dictionary/factor,
  - list/nested columns,
  - NA-only columns,
  - zero-copy views,
  - IPC read/write
- Explicit documentation of the difference between:
  - Arrow backend capabilities,
  - public language entry points,
  - fallback behavior

### Missing or incomplete implementation items

The main implementation gaps that stand out from the current code are:

1. **Public CSV path still has a split implementation**
   - The default `read_csv()` path now uses `Arrow_io.read_csv`, but option-rich parsing still uses the OCaml parser path.
   - This is now mostly a documentation and consistency question rather than a missing integration.

2. **Native datetime round-trip/materialization**
   - Date is present; datetime/timestamp support is only partial.

3. **Broader native materialization coverage**
   - list-column support is constrained to compatible nested schemas.

4. **Documentation/source alignment**
   - some docs still describe features as missing even though they are implemented.

5. **Historical spec cleanup**
   - older planning docs still describe the backend as “not started” or “stubbed,” which is useful historically but confusing if read as current status.

## What the current tests cover

### Dedicated Arrow tests

The main dedicated Arrow coverage is in:

- `tests/arrow/test_arrow_integration.ml`
- `tests/arrow/test_arrow_performance.ml`
- `tests/arrow/test_owl_bridge.ml`
- `tests/test_arrow_native_runner.ml`
- `tests/test_arrow_helpers.ml`

`tests/dune` wires the Arrow tests into both the regular test runner and a dedicated Arrow-native runner.

#### `tests/arrow/test_arrow_integration.ml`

This file covers a lot of backend behavior already:

- FFI availability flag
- pure-OCaml table creation and schema access
- column lookup and basic table operations
- bridge conversions (`column_to_values`, `values_to_column`, `row_to_dict`)
- T-level CSV-driven DataFrame operations (`read_csv`, `select`, `filter`, `mutate`, `arrange`, pipelines)
- native-path visibility through `explain(...).native_path_active`
- compute module coverage for:
  - project
  - filter
  - sort
  - scalar arithmetic
  - grouping and grouped aggregation
- zero-copy view behavior
- temporal parsing helpers for date/timestamp string parsing
- dictionary/factor support, including ordered-factor round-trips
- list-column support, including:
  - native materialization
  - NA entries
  - empty/all-NA fallback behavior
  - sparse NA-heavy cases
  - repeated lifecycle queries
  - GC stress loops
  - T-level `nest`, `unnest`, and `slice` regressions

This is already a strong regression suite for the Arrow backend internals.

#### `tests/arrow/test_arrow_performance.ml`

This file is less about benchmarking precision and more about smoke-testing broader behavior at realistic sizes:

- native CSV read smoke path via `Arrow_io.read_csv`
- zero-copy numeric views on native-backed tables
- column-view helpers
- vectorized math functions
- column aggregations
- comparison operations
- larger-table operations at 10k / 100k / 1M rows
- group-by and grouped aggregation on larger data
- large-data math/comparison smoke tests

So this file already covers scale-oriented sanity checks, not just micro-features.

#### `tests/arrow/test_owl_bridge.ml`

This file covers Arrow-to-statistics integration:

- numeric extraction through the bridge
- `lm()` behavior through the bridge
- `cor()` behavior through the bridge
- error handling for missing columns, bad input types, and NA cases

### Pipeline-level Arrow coverage

Arrow also appears in pipeline tests such as:

- `tests/pipeline/test_arrow_interop.t`
- `tests/pipeline/test_factor_roundtrip.t`
- several GLM / lab / PMML pipeline tests that use `serializer = "arrow"` and/or `deserializer = "arrow"`

These tests show that Arrow is not just a local DataFrame backend. It is also being used as the interchange format between T, R, and Python pipeline nodes.

That is important coverage, even though it is spread across the pipeline suite rather than grouped under `tests/arrow/`.

## What tests should be added next

The current tests are strong, but there are still some obvious gaps.

### Highest-priority tests to add

1. **Broaden Arrow IPC round-trip coverage**
   - Dedicated tests already exist for:
     - `Arrow_io.read_ipc`
     - `Arrow_io.write_ipc`
     - `read_arrow`
     - `write_arrow`
   - Round-trips now cover:
     - primitive tables,
     - dictionary/factor tables,
     - list-column tables where supported,
     - NA-only columns.
   - The remaining useful additions are edge cases such as empty structures and future datetime/timestamp coverage.

2. **Public `read_csv()` path tests that distinguish implementation path**
   - The repository currently tests `read_csv()` behavior, but not the architectural distinction between:
     - builtin `read_csv`,
     - backend-native `Arrow_io.read_csv`.
   - We should add tests that make this difference explicit so future refactors do not silently change backend behavior.

3. **Datetime/timestamp support tests**
   - The code currently tests timestamp parsing helpers, but not a full native round-trip story.
   - Add tests for:
     - datetime columns in DataFrames,
     - expected fallback behavior where native rebuild is unsupported,
     - eventual native round-trip once implemented.

4. **IPC/pipeline regression tests for Arrow serializer helpers**
   - There is already meaningful Arrow serializer/deserializer coverage through `tests/pipeline/test_arrow_interop.t` and other pipeline fixtures.
   - A smaller focused `read_node`/serializer boundary test would still be useful so this behavior is not covered only through broader end-to-end scenarios.

### Good next regression additions

5. **Deeply nested list-column tests**
   - The regression spec already calls out deeper list nesting as a useful target.

6. **List-column containing dictionary/factor sub-fields**
   - This is called out in `spec_files/arrow-regression-testing.md` and would exercise a high-risk interaction.

7. **Multi-chunk Arrow array tests**
   - The FFI explicitly combines chunked arrays, but there is no obvious dedicated regression test for multi-chunk column recombination.

8. **NA-only and empty-structure IPC tests**
   - Current tests cover some fallback behavior, but dedicated IPC round-trip checks would be valuable.

9. **Tests that assert docs-visible behavior**
   - For example, tests or snapshots around `explain(df).storage_backend` and `native_path_active` for representative schemas.

## What documentation should be added or updated next

### Add

1. **A dedicated user-facing Arrow I/O page**
   - `docs/reference/read_arrow.md` and `docs/reference/write_arrow.md` already exist.
   - The remaining gap is a broader narrative page that explains Arrow IPC workflows and where they are used.

2. **A support matrix page or section**
   - per type / operation:
     - supported natively,
     - supported with fallback,
     - not yet implemented.

3. **Better docs surfacing for the current status page**
   - link this page from the main Arrow-related docs so readers can find the implementation-status overview without searching `spec_files/` or `docs/`.

### Recently closed gap

- **NA-only native rebuild/materialization**
  - `NAColumn` can now be materialized back into a native Arrow table, which means NA-only DataFrames can remain on the native Arrow path and participate in Arrow IPC round-trips.

### Update

1. **`docs/performance.md`**
   - update rebuild/fallback examples so they match the current code.
   - In particular, dictionary, list, and date support should be described more accurately.

2. **`docs/architecture.md`**
   - add a clearer summary of Arrow IPC and pipeline interop, not just the table backend.

3. **Docs for `read_csv()`**
   - document the current reality:
     - what the user-facing builtin does today,
     - how it relates to `Arrow_io.read_csv`,
     - whether the native CSV reader is backend-only or intended to become the default path.

4. **Potentially annotate older spec files as historical**
   - especially files that still say Arrow is “not started” or “stubbed.”

## Recommended next steps

If the goal is to make Arrow status clear and reduce confusion, the best next steps are:

1. **Unify or explicitly document the CSV story**
   - either switch the public `read_csv()` builtin to `Arrow_io.read_csv`,
   - or document why the current split exists.

2. **Add dedicated Arrow IPC round-trip tests**
   - this is the clearest missing test area.

3. **Document the current support matrix**
   - especially for dictionary, list, date, datetime, and NA-only columns.

4. **Refresh stale docs/spec language**
   - so readers can distinguish:
     - historical plans,
     - current implementation,
     - future work.

5. **Add focused pipeline Arrow IPC regression tests**
   - especially around `read_node` and serializer/deserializer boundaries.

## Bottom line

Arrow in this repository is no longer a speculative or early-stub feature. It is a real backend with:

- native tables,
- native compute hooks,
- Arrow IPC,
- pipeline interchange,
- zero-copy numeric access,
- factor/list/date support,
- and meaningful regression coverage.

What is missing is not “Arrow support” in general. What is missing is:

- clearer status documentation,
- a more unified public entry-point story,
- fuller IPC-focused tests,
- and cleanup of outdated planning language that no longer reflects the current codebase.
