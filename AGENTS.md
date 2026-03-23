# Agent Contribution Guide

This file provides instructions for AI agents (and human contributors) working on the **T programming language** codebase. Read it carefully before making any changes.

---

## Table of Contents

- [Development Environment](#development-environment)
- [Project Overview](#project-overview)
- [Code Safety Rules](#code-safety-rules)
- [Function Conventions](#function-conventions)
- [Adding New Features](#adding-new-features)
- [Testing Requirements](#testing-requirements)
- [Documentation Requirements](#documentation-requirements)
- [Syntax and Behaviour Changes](#syntax-and-behaviour-changes)
- [Commit and PR Workflow](#commit-and-pr-workflow)

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
```

**Do not edit `flake.nix` unless absolutely necessary.** The only valid reason to touch it is to add a new system-level dependency required by newly developed functionality (e.g., a new C library or OCaml package). Any such change must be discussed and justified in the PR description.

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

6. **Strict Variable Lookup & Known Symbols.** Unbound variables evaluate strictly to a `NameError`. They do not silently fall back to symbols. However, to support convenient "bare word" syntax in pipeline configurations, certain names (like `R`, `Python`, `T`, `write_rds`, `default`) are explicitly pre-registered as `VSymbol` in `src/packages/core/packages.ml` via the `known_symbols` list. **If you introduce a new runtime or a new standard serializer, you MUST add its name to `known_symbols`** so users can write `runtime = Julia` instead of `runtime = "Julia"`.

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

- **Unit tests**: add `tests/unit/test_<function_name>.ml` (OCaml) and register it in the corresponding `dune` file.
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

---

## Testing Requirements

### Unit Tests (OCaml)

Located in `tests/unit/`. Each test file follows the same pattern:

```ocaml
open Ast
open Eval

let test_my_function () =
  let env = base_env () in
  let result = eval env (parse "my_function([1, 2, 3])") in
  assert (result = VFloat 2.0)

let () =
  List.iter (fun (name, test) ->
    try test (); Printf.printf "✓ %s\n" name
    with e -> Printf.printf "✗ %s: %s\n" name (Printexc.to_string e)
  ) [("my_function_basic", test_my_function)]
```

Register the test in the corresponding `tests/unit/dune` file:
```sexp
(test
 (name test_my_function)
 (libraries t_lang))
```

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

Documentation should follow the style of existing files. Use the `--#` format for inline docstrings, plain Markdown for `docs/` pages.

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

1. Make changes in a focused branch.
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
