# Agent Contribution Guide

This file provides instructions for AI agents (and human contributors) working on the **T programming language** codebase. Read it carefully before making any changes.

---

## Table of Contents

- [Development Environment](#development-environment)
- [Quick Feedback with t check](#quick-feedback-with-t-check)
- [Project Overview](#project-overview)
- [Code Safety Rules](#code-safety-rules)
- [Function Conventions](#function-conventions)
- [Adding New Features](#adding-new-features)
- [Testing Requirements](#testing-requirements)
- [Troubleshooting and Fixing Tests](#troubleshooting-and-fixing-tests)
- [Documentation Requirements](#documentation-requirements)
- [Syntax and Behaviour Changes](#syntax-and-behaviour-changes)
- [Commit and PR Workflow](#commit-and-pr-workflow)
- [Maintenance and Release](#maintenance-and-release)

---

## Development Environment

**Always use the provided Nix flake** to obtain the correct toolchain. This is non-negotiable — T's reproducibility guarantee depends on it.

```bash
# Enter the development shell (do this first, every time)
nix develop

# Build the project
dune build

# Run all tests
dune runtest

# Run the REPL
dune exec src/repl.exe

# Run a T script
dune exec src/repl.exe -- run myfile.t

# Check a T script for structural errors (instant, no Nix builds)
t check myfile.t

# Check with column-level schema validation
t check --schema myfile.t

# Watch mode: re-run on file save
t check --watch myfile.t

# Compare two builds (output diff)
t diff myfile.t

# Build with coverage instrumentation (Nix)
nix build .#t-coverage
./result/bin/t run myfile.t
./result/bin/bisect-ppx-report html
```

**Do not edit `flake.nix` unless absolutely necessary.** The only valid reason to touch it is to add a new system-level dependency required by newly developed functionality (e.g., a new C library or OCaml package). Any such change must be discussed and justified in the PR description.

---

## Quick Feedback with `t check`

When implementing or modifying pipeline nodes, use `t check` for instant structural validation **without triggering Nix builds**. This is the fastest way to catch errors during development.

### Three tiers of checking

| Command | What it checks | Nix required? |
|---------|---------------|---------------|
| `t check <file.t>` | Pipeline DAG structure, dependency cycles, node syntax | No |
| `t check --schema <file.t>` | + column references, schema propagation | No |
| `t check --env <file.t>` | + `tproject.toml` declarations, lockfile consistency, Nix eval | Yes |
| `t check --json <file.t>` | Structured JSON diagnostics (works with any tier) | Depends on tier |

**Always run `t check` before `dune runtest`.** It catches structural errors in seconds without needing Nix or runtime dependencies.

### Watch mode

Use `--watch` during active development for continuous feedback:

```bash
t check --watch --schema src/pipeline.t
```

This runs immediately, then re-runs on every file save. Press Ctrl+C to stop. Exit code reflects the last check's diagnostics.

### Workflow for implementing a new pipeline node

1. Write the node in your pipeline script
2. Run `t check --schema src/pipeline.t` — verify no errors
3. Run `dune runtest` — full test suite
6. Run `build_pipeline(p)` — Nix build (only when structural checks pass)

### Agent Check-Fix Loop Rules (Critical for LLMs)

- **`t fix` is Not Idempotent:** `t fix` does not check if a suggestion was already applied. If you run `t check` -> `t fix` in a loop, you must count the number of diagnostics/errors returned. If the count does not decrease after a fix, **stop immediately** and do not run `t fix` again; otherwise, you will insert duplicate code blocks (e.g. repeated cast mutations).
- **Suggested Fix Confidence Levels:** Every suggested fix contains a `"confidence"` string field in JSON (`"high"`, `"medium"`, or `"low"`) indicating whether the fix is deterministic or heuristic. Confidence is computed dynamically from diagnostic context, not static per fix kind:
  - `Cast`: `"high"` when schema chain is intact, `"medium"` when broken (missing upstream column)
  - `Rename_column`: `"high"` at edit distance 1 and unique, `"medium"` at distance 2, `"low"` at 3+
  - `Rename_node`: always `"medium"` (the `_node` name choice is deterministic, but `t fix` refuses to apply when the node is referenced elsewhere in the file — `deps` entries, sibling expressions, or other nodes' raw code blocks — since those cannot be rewritten safely at the text level; rename references manually)
  - `Add_node_arg`: always `"medium"` (heuristic, verify before applying)
  - `Suggest_identifier`: `"high"` at distance 1 and unique, scales down with distance/uniqueness
  - `Run_command`: always `"low"` (actionable commands, check manual commands before execution)
  - **Note:** `t fix` applies all non-`NoFix` suggestions regardless of confidence. Confidence is informational for agents/tools to decide whether to auto-apply or review first.
- **Avoid Watch Mode:** Do NOT use `--watch` (e.g., `t check --watch`). It runs a blocking loop that waits for file changes and requires a manual `Ctrl+C` interrupt, which hangs agent execution.
- **Schema Silencing on Custom Verbs:** If you use a custom or unrecognized function in a pipe chain, the schema compiler drops the schema to empty (`[]`). This silences subsequent column-reference checks downstream. Always manually verify column references if custom verbs are introduced.

---

## Project Overview

The repository is structured as follows:

```
tlang/
├── src/
│   ├── ast.ml              # AST definition — all value and expression types
│   ├── lexer.mll           # Lexer (ocamllex)
│   ├── parser.mly          # Parser grammar (Menhir)
│   ├── eval.ml             # Tree-walking evaluator
│   ├── repl.ml             # REPL and CLI entry point
│   ├── error.ml            # Structured error constructors
│   ├── arrow/              # Apache Arrow C GLib FFI bindings
│   ├── ffi/                # Other foreign function interface utilities
│   └── packages/           # Standard library (one sub-directory per package)
│       ├── base/           # Errors, NA values, assertions
│       ├── core/           # Functional primitives (map, filter, fold, …)
│       ├── math/           # Mathematical functions
│       ├── stats/          # Statistical functions (mean, sd, lm, …)
│       ├── dataframe/      # CSV I/O, DataFrame operations
│       ├── colcraft/       # Data verbs (filter, mutate, arrange, …)
│       ├── pipeline/       # Pipeline introspection and manipulation
│       └── explain/        # Debugging and introspection tools
├── tests/
│   ├── unit/               # OCaml unit tests (*.ml)
│   ├── golden/             # Golden tests — T output compared against R/Python
│   │   ├── t_scripts/      # .t programs run by T
│   │   ├── data/           # Generated CSV datasets (git-ignored)
│   │   ├── expected/       # Expected outputs from R (git-ignored)
│   │   └── t_outputs/      # T outputs for comparison (git-ignored)
│   └── integration/        # End-to-end integration tests
├── docs/                   # Documentation (Markdown + compiled HTML)
├── examples/               # Example T programs
├── scripts/                # Developer helper scripts
├── flake.nix               # Nix development environment — do not edit lightly
├── Makefile                # Golden test targets (make golden, make golden-quick, …)
├── dune-project            # Dune build system configuration
└── summary.md              # High-level feature and status summary (keep up to date)
```

### Key Source Patterns

- **`src/packages/<pkg>/<function>.ml`** — Each function lives in its own file and calls `Env.add` to register itself.
- **`src/packages/<pkg>/loader.ml`** (or similar) — Aggregates all functions in a package and loads them into the environment.
- **`src/error.ml`** — Use the structured error constructors (`Error.type_error`, `Error.value_error`, `Error.arity_error`, …). Never raise raw OCaml exceptions from user-facing code.
- **`src/ast.ml`** — The canonical source of truth for all `value` variants (`VInt`, `VFloat`, `VBool`, `VDataFrame`, `VError`, …).

---

## Code Safety Rules

These rules are **mandatory** and apply to every line of OCaml code added or modified:

1. **No `unwrap`-style calls.** Never use `Option.get`, bare `List.hd` on potentially-empty lists, or any other function that can raise an exception on bad input without explicit prior validation.

2. **No partial pattern matches.** All `match` expressions must handle every reachable case. Use the catch-all `| _ ->` only when genuinely exhaustive handling is impossible, and document why.

3. **No raw OCaml exceptions in user-facing paths.** Return `VError { … }` (or use the helpers in `error.ml`) instead of `failwith`, `raise`, or `assert false`. OCaml exceptions are acceptable only for truly unexpected internal invariant violations that represent programmer error, not user error.

4. **No mutable state unless strictly necessary.** Prefer `let` bindings and functional style. When mutable references (`ref`) are needed (e.g., accumulating errors in a loop over an array), document why.

5. **No silent NA propagation.** Functions that receive NA values must either propagate the error explicitly or respect an `na_rm` parameter, consistent with the rest of the standard library.

6. **Strict Variable Lookup & Known Symbols.** Unbound variables evaluate strictly to a `NameError`. They do not silently fall back to symbols. However, to support convenient "bare word" syntax in pipeline configurations, certain names (like `R`, `Python`, `T`, `Julia`, `Quarto`, `sh`, `write_rds`, `default`) are explicitly pre-registered as `VSymbol` in `src/packages/core/packages.ml` via the `known_symbols` list. **If you introduce a new runtime or a new standard serializer, you MUST add its name to `known_symbols`** so users can write `runtime = Julia` instead of `runtime = "Julia"`.

7. **No Silent Magic.** Never implement "placeholders" that appear to work by secretly substituting requested behavior with a fallback (e.g., never silently use JSON if ONNX serialization is requested but unsupported). If an operation cannot be performed natively and correctly as requested, always return an explicit `VError` with a helpful message. Transparency and developer predictability are prioritized over "magical" implicit success.

8. **Death to Null.** Under no circumstances should `null` be implemented or used. Missingness is handled via `NA` and optionality via `Error` or explicit missing values.

9. **Absolute Explicitness.** No implicit behavior: all configuration, pipeline dependencies, and environment assumptions must be declared explicitly so that the codebase serves as its own complete documentation.

**Pattern to follow** (from `src/packages/stats/mean.ml`):
```ocaml
(* Good: return VError, never raise *)
| Some (VNA _) -> Error.type_error "Function `mean` encountered NA value. Handle missingness explicitly."
| Some _ -> Error.type_error "Function `mean` expects a numeric List or Vector."
| None -> Error.arity_error_named "mean" ~expected:1 ~received:(List.length args)
```

**Anti-pattern to avoid**:
```ocaml
(* Bad: can raise at runtime *)
let hd = List.hd args          (* raises on empty list *)
let v  = Option.get maybe_val  (* raises on None       *)
failwith "unexpected input"    (* unstructured error   *)
```

---

## Function Conventions

### Data Argument Comes First

For **every** function that takes a data argument (a `DataFrame`, `Vector`, `List`, or `Model`), **the data argument must be the first positional parameter**. This is required for the pipe operator (`|>`) to work correctly and is a core language convention.

```ocaml
(* Good: data first *)
| [VDataFrame df; fn] -> ...   (* filter(df, predicate) *)
| [VDataFrame df]     -> ...   (* nrow(df) *)

(* Bad: data not first — breaks pipe operator *)
| [fn; VDataFrame df] -> ...
```

This applies equally to:
- OCaml native function registrations (`make_builtin`, `make_builtin_named`)
- T-language standard library functions written in `.t` files
- Any new utility functions added to a package

### Named / Optional Arguments

- Required arguments come first (positional).
- Optional arguments (e.g., `na_rm`, `clean_colnames`, `direction`) come last as named arguments.
- Default values must be explicit and consistent with R's tidyverse conventions where applicable.

### No Aliases

**Never create aliases** for existing functions (e.g., do not add `read_pmml` if `t_read_pmml` already exists). Aliases are confusing and serve no purpose. Always use the canonical name.

When you encounter an existing alias, you should:
1.  **Identify the canonical name** (usually the one that is more consistent with T's naming conventions or R's tidyverse).
2.  **Use `scripts/refactor_alias.sh <old_name> <new_name>`** to replace the alias across the entire codebase (including documentation).
3.  **Delete the alias registration** in the OCaml source.
4.  **Verify with `scripts/audit_aliases.sh`**.

---

## Refactoring and Code Health

Maintaining a clean and unified codebase is a priority. Use the following tools and patterns to ensure system integrity:

### 1. Unified Utility Modules
When implementing new functions, check if similar logic already exists in utility modules:
-   **`Math_utils.ml`**: Canonical source for numeric extraction (`extract_numeric_array`), statistical primitives (`mean_array`, `variance_array`), and weight handling.
-   **`Math_common.ml`**: Shared constants and configuration flags.

### 2. Audit Scripts
The `scripts/` directory contains tools for automated health checks:
-   **`scripts/audit_aliases.sh`**: Detects usage of known deprecated aliases.
-   **`scripts/audit_docs.py`**: Verifies that every exported function has a corresponding `--#` docstring block.
-   **`scripts/refactor_alias.sh`**: A utility to safely rename functions and update all references.

### 3. Detecting Implicit Aliases in OCaml
When performing an audit, look for these common OCaml patterns that create undocumented aliases:
-   **Direct Assignment**: `let alias = original` (Look for this in package files).
-   **Double Registration**: Calling `Env.add "alias" func` and `Env.add "original" func` in the same module.
-   **Lookup Re-registration**: `Env.add "alias" (Env.find "original" env)`.

If you find such patterns, unify them under a single canonical name unless there is a strong backward-compatibility reason to keep the alias (in which case, document it as such in the source).

### Error Handling

Use the structured helpers from `src/error.ml`:

| Situation | Constructor |
|-----------|-------------|
| Wrong type for an argument | `Error.type_error "…"` |
| Invalid value (out of range, etc.) | `Error.value_error "…"` |
| Wrong number of arguments | `Error.arity_error "…"` or `Error.arity_error_named` |
| General runtime error | `make_error RuntimeError "…"` |

Error messages should name the function and describe what went wrong:
```ocaml
make_error TypeError "Function `filter` expects a DataFrame as first argument."
```

---

## Adding New Features

Follow this checklist whenever you add a new function or language feature:

### 1. Implement

- Add `src/packages/<package>/<function_name>.ml` (or extend an existing file if it is a trivial variant).
- Register the function with `Env.add` inside a `register` function.
- Ensure the data argument is first (see above).
- Return `VError` — never raise — on all invalid inputs.
- Do not use `Option.get`, `List.hd` on unvalidated lists, or any other partial function.

### 2. Add Tests

- **Unit tests**: add a test module in the appropriate `tests/` subdirectory. Use `test` for stateless assertions, `test_env` when the test depends on prior env state. Register the module in `test_runner.ml` with `run` (for `test`-only modules) or `run_with_env` (for modules using `test_env`), and in the corresponding `dune` file.
- **Golden tests** (preferred for numerical or statistical functions): add a `.t` script in `tests/golden/t_scripts/`, a matching R script in `tests/golden/r_scripts/` (or extend `generate_expected.R`), and a `test_that(…)` block in `tests/golden/test_golden_r.R`.

  Golden tests are **required** for any function that produces numeric or statistical output that can be verified against R or Python.

- Run tests before committing:
  ```bash
  dune runtest           # unit tests
  make golden-quick      # golden tests (assumes data already generated)
  ```
  Fix all failures. Keep fixes small and surgical — do not change unrelated tests or code.

### 3. Update Documentation

- Add or update the docstring comment block at the top of the `.ml` file (follow the `--#` format used throughout `src/packages/`):
  ```ocaml
  (*
  --# Short one-line description
  --#
  --# Longer description.
  --#
  --# @name my_function
  --# @param data :: DataFrame The input data frame.
  --# @param na_rm :: Bool = false Remove NA values before computation.
  --# @return :: Float The result.
  --# @example
  --#   my_function(df, na_rm = true)
  --# @family <package-name>
  --# @export
  *)
  ```
- Add an entry to `docs/api-reference.md` under the correct package section.
- Add a usage example to the relevant section of `README.md` if the function is user-facing and significant.
- Update `docs/` with a more detailed explanation if the feature is non-trivial (see existing docs for style).

### 4. Update `summary.md`

Always update `summary.md` in the repository root to reflect new functionality. Follow the existing format (feature name, brief description, status).

### 5. Update Tree-sitter Highlights

When adding new builtins to the standard library, you **must** update the `#match?` regex in `editors/tree-sitter-t/queries/highlights.scm` to ensure the new functions are correctly highlighted in supported editors.

---

## Testing Requirements

### Test Infrastructure

All OCaml tests are orchestrated by `tests/test_runner.ml`, which provides shared helpers and counts pass/fail across all modules. **Do not write standalone test runners** — add your test function to a module registered in `test_runner.ml`.

#### Helpers

| Helper | Signature | Use when |
|--------|-----------|----------|
| `test name input expected` | Evaluates `input` against `shared_env`, compares string output to `expected`. | The test expression doesn't depend on prior state (no CSV loads, no pipeline setup). |
| `test_env env name input expected` | Evaluates `input` against an explicit `env`, compares string output to `expected`. | The test depends on prior state — e.g. a CSV was loaded, a pipeline was created, or a variable was bound earlier in the same test. |

Both helpers:
1. Try exact string match first.
2. Fall back to substring match if the exact match fails.
3. Strip `[L1:C1]` location markers from results before comparing.

**Regex semantics differ between the two:**
- `test` fallback uses the expected string as a live `Str` regex — `.`, `[`, `]`, `*` are metacharacters. Use `{|...|}` delimiters for patterns containing these intentionally (e.g. `{|.*t check.*|}`).
- `test_env` fallback wraps the expected string in `Str.quote` — all metacharacters match literally. This is the safer default for new tests.

#### When to keep OCaml-level assertions

Use `test`/`test_env` for all simple assertions. Keep OCaml-level assertions (manual `incr pass_count` + pattern matching) only when the test requires:
- **Float comparison with tolerance** — e.g. `Float.abs (slope -. 1.0) < 0.001` (see `test_formula_edge_cases.ml`)
- **Multi-step try/with with env injection** — e.g. evaluating an expression, catching an exception, then injecting the result into a new env for a follow-up check (see `test_colcraft_edge_cases.ml`)
- **Substring/contains checks** — `test_env` does substring matching, but if you need to assert the *absence* of a substring, or use a custom predicate, use OCaml-level code

Never use manual `incr pass_count` for assertions that `test`/`test_env` can express — it's error-prone (easy to increment on both branches of an if/else) and can hide individual hollow branches that strict mode's module-level check won't catch.

### Unit Tests (OCaml)

Located in `tests/` subdirectories (`unit/`, `golden/`, `stats/`, `colcraft/`, etc.). Each test module exposes a `run_tests` function.

**Module using `test` only** (most common):

```ocaml
(* tests/unit/test_my_thing.ml *)
let run_tests pass_count fail_count _failures _eval_string _eval_string_env test =
  Printf.printf "My Thing:\n";
  test "basic arithmetic"
    "1 + 2"
    "3";
  test "string length"
    "length(\"hello\")"
    "5"
```

**Module using `test_env`** (when test depends on prior state):

```ocaml
(* tests/colcraft/test_my_thing.ml *)
let run_tests pass_count fail_count _failures _eval_string eval_string_env test test_env =
  Printf.printf "My Thing:\n";
  let env = Packages.init_env () in
  let (_, env) = eval_string_env {|df = read_csv("data/test.csv")|} env in
  test_env env "nrow after filter"
    {|df |> filter($x > 5) |> nrow|}
    "3"
```

**Register in `tests/test_runner.ml`:**

```ocaml
(* For modules using `test` only: *)
run "Test_my_thing" Test_my_thing.run_tests;

(* For modules using `test_env`: *)
run_with_env "Test_my_thing" Test_my_thing.run_tests;
```

**Register in the corresponding `dune` file:**

```sexp
(test
 (name test_my_thing)
 (libraries t_lang))
```

### Strict Mode

Set `TLANG_TEST_STRICT=1` to enable strict mode. The `run_module` wrapper tracks assertion counts per module and reports any module that produced **zero assertions** — catches hollow tests that print but never assert.

```bash
TLANG_TEST_STRICT=1 dune exec tests/test_runner.exe
```

### Mutation Testing

`scripts/mutation_test.sh` verifies the test suite catches real regressions by temporarily breaking known code paths and confirming tests fail.

```bash
./scripts/mutation_test.sh              # run all 9 mutations
./scripts/mutation_test.sh integer_add  # run a single mutation
```

Current mutation targets:

| Name | File | What it breaks | What catches it |
|------|------|---------------|-----------------|
| `integer_add` | `src/eval.ml` | `a + b` → `a * b` | Arithmetic tests |
| `if_else_swap` | `src/eval.ml` | Swaps `then_`/`else_` branches | Conditional logic tests |
| `unary_not` | `src/eval.ml` | `not b` → `b` (identity) | Boolean negation tests |
| `na_silent_pass` | `src/eval.ml` | NA error → silent `VNA` return | NA propagation tests |
| `arrow_add_scalar` | `src/arrow/arrow_compute.ml` | Float add → subtract in `add_scalar` | Scalar operation tests |
| `arrow_compare_gt` | `src/arrow/arrow_compute.ml` | `Gt` comparison → `Lt` | Comparison/filter tests |
| `clean_safe_char` | `src/packages/dataframe/clean_colnames.ml` | `c >= 'a'` → `c > 'a'` (excludes `'a'`) | Column name cleaning tests |
| `clean_collision` | `src/packages/dataframe/clean_colnames.ml` | Collision counter `count + 1` → `count - 1` | Duplicate column name tests |
| `csv_type_fallback` | `src/packages/dataframe/t_read_csv.ml` | String fallback → `VInt 0` | CSV type inference tests |
| `global_deps_guard` | `src/packages/pipeline/set_pipeline_global_options.ml` | `p_explicit_deps` rewritten unconditionally (flips `None` → `Some []`) when `dependencies` omitted | `set_pipeline_global_options` deps-omitted regression test |

The script verifies each mutation was actually applied (via `diff -q`) before building/testing. If a mutation pattern doesn't match the current source, it reports "pattern did not match" instead of a false SURVIVED. The backup/restore mechanism uses an associative array to support mutations across multiple source files.

**Mutation-test hygiene:** if `mutation_test.sh` is interrupted or aborted mid-run, the target source file can be left mutated (e.g. `src/eval.ml`) and a `.bak` file left behind. After any run, verify with `git status` that no unexpected `.ml` files are modified and no stray `*.bak` files exist. Restore with `git checkout <file>` and `rm <file>.bak`.

### Golden Tests (T vs R)

Located in `tests/golden/`. These compare T output to R/dplyr output:

**T script** (`tests/golden/t_scripts/my_test.t`):
```t
df = read_csv("tests/golden/data/mtcars.csv")
result = df |> my_function($mpg)
write_csv(result, "tests/golden/t_outputs/my_test.csv")
```

**R expected output** (add to `tests/golden/generate_expected.R`):
```r
mtcars %>%
  my_r_equivalent(mpg) %>%
  save_output("my_test", "Description of what is being tested")
```

**Assertion** (add to `tests/golden/test_golden_r.R`):
```r
test_that("my_function produces correct output", {
  compare_csvs("my_test")
})
```

Run the full golden pipeline:
```bash
make golden
```

Or just re-run T scripts and compare (when data already exists):
```bash
make golden-quick
```

**When T and R disagree:** If T's behavior is correct but differs from R (e.g. tie-breaking, NA handling, sort stability), maintain the expected CSV manually (checked-in) and remove the generation block from `generate_expected.R` (so it isn't auto-overwritten), but keep the `compare_csvs(...)` call in `test_golden_r.R` so the manually-maintained CSV is still enforced. Add a `#` comment in both files explaining why.

---

## Troubleshooting and Fixing Tests

If tests fail during development, follow this guide to identify and fix common issues:

### 0. `✗` lines in `dune runtest` output are not always failures
**Symptoms**: `dune runtest` prints `✗ tests/test-fail.t` and `✗ tests/test-syntax.t`
with an `Assertion failed.` line, yet exits 0.
**Cause**: `tests/test_misc_coverage.ml` deliberately writes broken fixtures
(`assert(helper_value == 0)` and a syntax error) and asserts that `t test`
reports them as failures. The `✗`/`Assertion failed.` text is that fixture
runner's expected output.
**Fix**: None — it is intended behaviour. Do not "fix" these files. Treat a
`dune runtest` exit code of 0 as green even when such lines appear.

### 1. NameError: Variable Shadowing
**Symptoms**: `Error(NameError: "[L1:C1] Variable 'x' is immutable and cannot be reassigned.")`
**Cause**: You are attempting to assign a value to a variable name that is already a reserved built-in function (e.g., `summary`, `mean`, `print`). 
**Fix**: Rename the variable in your test script (e.g., use `res` or `val` instead of `summary`).

### 2. KeyError: Column not found in DataFrame
**Symptoms**: `Error(KeyError: "[L1:C50] Column 'node_count' not found in DataFrame.")`
**Cause**: Many introspection functions like `pipeline_to_frame(p)` return a **DataFrame** (one row per node) rather than a **Dict**.
**Fix**: Use `nrow(res)` to check the node count, or `length(pipeline_edges(p))` for the edge count. Do not attempt to access `.node_count` or `.edge_count` as if they were record fields on the result.

### 3. Dependency Check Failures
**Symptoms**: `Error(FileError: "Dependency Check Failure: Missing R package 'jsonlite' in tproject.toml")`
**Cause**: The project enforces **Explicit Dependency Declaration**. Automatic dependency injection is disabled by default in the Nix emitter. CI workflows do not set `TLANG_AUTO_ADD_PIPELINE_DEPS=1`; tests and local runs must not rely on that flag being present.
**Fix**: 
- If the test is intended to fail without dependencies, update the expectation to match the `FileError`.
- If the test should succeed, ensure a `tproject.toml` is present in the test environment. Do not rely on `TLANG_AUTO_ADD_PIPELINE_DEPS=1` being set; use `build=false` in `populate_pipeline` if only static analysis is being tested.

### 4. Nix Build Failures in Tests
**Symptoms**: `✖ Pipeline build failed [General Nix build failure]` during `dune runtest`.
**Cause**: Tests calling `build_pipeline(p)` trigger a real Nix build. This may fail in sandboxed environments if the local `t-lang` source cannot be resolved.
**Fix**: Prefer `populate_pipeline(p, build=false)` for unit tests that only verify Nix emission or dependency analysis. Reserve `build_pipeline` for full integration tests in `tests/integration/`.

### 5. `nix develop` fails with "don't know how to recreate store derivation"
**Symptoms**: `nix develop` aborts with
`error: don't know how to recreate store derivation '/nix/store/<hash>-nix-shell.drv'!`
and every subsequent `nix develop`-wrapped command (build/test/REPL) fails the same way.
**Cause**: The Nix store derivation backing the dev shell was garbage-collected out of
the store while the flake's evaluation cache still references it. This typically appears
after a `nix-store --gc` run or when the store is under memory pressure.
**Fix**: Clear Nix's evaluation cache so the shell derivation is recreated on next use:
```bash
rm -rf ~/.cache/nix/eval-cache-*
nix develop
```
After clearing the cache the shell (and its wrapped commands such as `dune build`,
`dune runtest`, and `t`) works again. This is safe — the cache is only a speed-up.

---

## Documentation Requirements

Every new user-facing feature must be documented **before the PR is merged**:

| Location | What to update |
|----------|----------------|
| `src/packages/<pkg>/<fn>.ml` | `--#` docstring block |
| `docs/api-reference.md` | Function signature, parameters, return type, example |
| `README.md` | High-level mention if the feature is significant |
| `summary.md` | One-line entry in the feature list |
| `docs/<topic>.md` | Detailed guide if the feature is complex |

### Changelog Guidelines

When updating `docs/changelog.md`, always focus on features, enhancements, and bug fixes from the **user's perspective**. 

- **Do not mention fixing tests** or test suite adjustments. Reliable testing is a baseline expectation for all contributions; mentioning it in the public changelog is unnecessary noise for users.
- Emphasize the new capabilities or resolved user-facing issues (e.g., say "Implemented weights argument" instead of "Fixed failing weighted tests").

---

---

## Syntax and Behaviour Changes

**Do not make assumptions that require changing existing syntax or behaviour.** If a new feature requires:

- Modifying the parser (`src/parser.mly`) or lexer (`src/lexer.mll`) in a way that could break existing scripts,
- Changing the semantics of an existing function,
- Changing the evaluation order or scoping rules,

**stop and ask the human maintainer for validation before proceeding**. Describe the proposed change, why it is needed, and what existing behaviour would be affected. Do not implement the change until you have explicit approval.

Safe changes (no approval needed):
- Adding entirely new functions that do not conflict with existing names.
- Adding optional named arguments with default values that preserve existing call signatures.
- Adding new packages or modules that are opt-in.

---

## Commit and PR Workflow

1. **Branch Management**: NEVER push straight to `main` unless explicitly told otherwise. Always push to a new branch or the currently checked-out branch if it is different from `main`. In case of doubt, ALWAYS ask before pushing!
2. **No Merging**: NEVER merge a branch into `main` or any other branch unless explicitly told to do so. Only the human maintainer merges.
2. Make changes in a focused branch.
2. Run `dune build` and `dune runtest` — all tests must pass.
3. Run `make golden-quick` if your change touches any statistical or data-manipulation function.
4. Ensure `docs/api-reference.md`, `README.md`, and `summary.md` are updated.
5. Write a clear commit message:
   ```
   feat(stats): add trimmed_mean function

   Implements trimmed_mean(data, trim, na_rm = false).
   Data argument comes first. Golden tests vs R's mean(x, trim = …).
   Updates api-reference.md and summary.md.
   ```
6. Open a pull request. The PR description should state:
   - What was added or changed.
   - Which tests cover the change.
   - Whether any syntax or existing behaviour was affected (and if so, whether it was approved).

---

## Maintenance and Release

### Versioning Policy for Agents

- **Never upgrade the version string** in the `VERSION` file or `docs/changelog.md` without an explicit request from the user. 
- Agents should only perform release workflows (like running `sync_version.sh` for a version bump) if specifically instructed to do so.
- When in doubt, stop and ask.

### Releasing a new version of T

T uses a single source of truth for its version. To release a new version:

1.  **Bump the Version**: Update the version string in the root [VERSION](./VERSION) file (e.g., `0.51.1`).
2.  **Sync Documentation**: Run the synchronization script to propagate the version to READMEs and documentation:
    ```bash
    ./scripts/sync_version.sh
    ```
3.  **Update Changelog**: Add the release notes and date to [docs/changelog.md](./docs/changelog.md).
4.  **Commit and Push**:
    ```bash
    git add .
    git commit -m "chore: release 0.5x.x"
    git push origin main
    ```
    *The GitHub Action in `.github/workflows/release.yaml` will automatically create the Git tag and GitHub Release.*

## OCaml Code Review Checklist

### Exceptions & Error Handling
- No bare `raise` / `failwith` / `invalid_arg` in business logic — should use `Result` or `option` instead
- No `List.hd`, `List.tl`, `Array.get` without bounds/pattern guard — these raise on empty/OOB
- No `Hashtbl.find` without a `find_opt` alternative — raises `Not_found`
- `try/with` blocks are narrow and specific — not wrapping huge chunks of code
- `with _ ->` or `with e ->` (catch-all) is a red flag — should match specific exceptions
- External/IO operations handle errors explicitly, not silently swallowed

### The Type System — Are You Using It?
- No `Obj.magic` anywhere — full stop
- No `Bytes.unsafe_*` or `Array.unsafe_*` unless in a hot path with a clear justification comment
- `option` values are pattern matched, not passed around and `Option.get`'d later
- `Result` values are not ignored — check for `let _ = some_result_returning_fn`
- Variant types have exhaustive pattern matches (no wildcard `_` hiding unhandled cases)
- No `ignore` on a `Result` or `option` without an explicit comment explaining why

### Mutability
- `ref` usage is local and justified — not used as a substitute for functional patterns
- Mutable record fields (`mutable`) are minimal and documented
- No global mutable state unless it's genuinely necessary (config, caches) and clearly marked
- Loops with accumulated `ref` variables — could these be `List.fold` instead?

### Module & Abstraction Hygiene
- `.mli` files exist for all significant modules — exposed interface is intentional, not accidental
- No leaking of internal types through the public interface
- Module signatures use abstract types where appropriate (not exposing the representation)
- Functors are used for parameterization, not copy-pasted modules

### Polymorphism & Type Inference Traps
- No over-reliance on polymorphic comparison (`=`, `<`, `>`) on complex types — use `compare` from a specific module or `ppx_compare`
- No structural equality (`=`) on floats — use `Float.equal` or explicit epsilon comparison
- Value restriction surprises — if something is unexpectedly monomorphized, understand why

### Effects & Purity
- Functions that perform I/O or mutation are clearly named or documented as such
- No hidden side effects inside `lazy` values or inside what looks like a pure computation
- `Printf`/logging calls are not scattered through pure business logic

### Warnings
- Code compiles with **zero warnings** — especially:
  - Warning 8: non-exhaustive pattern match
  - Warning 26/27: unused module binding / unused `open`
  - Warning 32: unused value declaration
  - Warning 39: unused functor parameter
- `-warn-error +a` (or equivalent in `dune`) is set in CI so warnings are hard errors

### Dependencies & Unsafe FFI
- C bindings (`external`) have a clear ownership/memory model documented
- No `Gc.compact` or manual GC calls without strong justification
- Foreign function calls validate inputs before passing to C

### Style Red Flags That Hide Bugs
- No deeply nested `match` inside `match` — extract to named functions
- No excessively long functions — hard to reason about control flow
- `begin/end` blocks are not masking complex branching logic
- `fun _ ->` (ignoring an argument) is intentional, not accidental
