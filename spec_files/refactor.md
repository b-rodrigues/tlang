# AI Agent Refactoring Guide: No Aliases, No Dead Code

This document provides a structured, step-by-step methodology for an AI agent to safely refactor the T-Lang codebase. The specific goal of this refactoring effort is to **remove aliases** (such as deprecated or duplicate function names) and **eliminate dead code** across the repository.

This work should be performed in the current branch (`julia-support-refactor`), which is stacked on `julia-support`.

## Agent Instructions
- Check off the items below using `[x]` as you complete them.
- Make atomic, focused commits after completing each major checklist item.
- If a test fails after a change, stop and fix the regression before proceeding to the next step.

---

## Phase 1: Baseline & Preparation

Before removing any code, ensure the current state is stable and well-understood.

- [x] **Establish Test Baseline**: Run the full test suite (`dune test` or equivalent) to ensure all tests are passing before making changes.
- [x] **Review Demos**: Verify that the pipelines in `t_demos` build successfully, as they act as our end-to-end integration tests.
- [x] **Generate Analysis**: Use `dune` warnings, `grep`, or OCaml dead code analysis tools to generate a list of unused functions, variables, and modules.

---

## Phase 2: Removing Aliases

Aliases create multiple ways to do the same thing, complicating the API and evaluation logic. The goal is to enforce one canonical name per operation.

- [x] **Identify Aliases**: Create a list of aliases currently in the language. Confirmed targets:
    - `ceil` → `ceiling`
    - `mday` → `day`
    - `to_numeric` → `to_float`
    - `to_factor` → `factor`
    - `py` → `pyn`
    - `jl_node` → `jln`
    - `casewhen` → `case_when`
- [x] **Search for Usages**: Use exact pattern matching to find all instances where the aliases are used in:
  - `src/` (Compiler and evaluator code)
  - `tests/` (Test scripts and assertions)
  - `docs/` (Documentation and examples)
  - `t_demos/` (Demo projects)
- [x] **Replace Usages**: Update all identified usages to use the canonical names.
- [x] **Remove Alias Definitions**: Delete the code that defines or registers the alias (e.g., in `packages.ml` or `eval.ml`).
- [x] **Continuous Verification**: After each alias removal, re-run `dune test` and the `t_demos` pipelines to catch any regressions.

## Phase 6: Documentation Integrity

Ensure that the refactored codebase remains user-friendly by verifying that all public-facing functions have associated documentation.

- [x] **Audit Public Functions**: Scan `src/packages/` to ensure every exported function has a `--#` TDoc comment block.
- [x] **Verify TDoc Metadata**: Check that `@name`, `@param`, and `@return` tags are present and accurate for each function.
- [x] **Rebuild Reference Manual**: Run the documentation generator to ensure `docs/reference.md` is complete and contains no broken links or missing entries.

---

## Phase 3: Dead Code Elimination

Remove unused types, variables, functions, and modules to keep the codebase lean and maintainable.

- [x] **Remove Unused Variables & Bindings**: Look for variables that are declared but never used (OCaml usually warns about these).
- [x] **Remove Unreachable Code**: Delete logic branches, match cases, or helper functions that can no longer be reached (especially after alias removal).
- [x] **Clean Up Standard Packages**: Review `src/packages/core/packages.ml` and `src/packages/` for built-in functions or modules that are no longer referenced or exported.
- [x] **Remove Orphaned Documentation**: Delete documentation files or comments for features/functions that have been removed.
- [x] **Prune Dependencies**: Check `tproject.toml` and `flake.nix` files (both in T-Lang and `t_demos`) for dependencies that are no longer required by the language or demos.
## Phase 6: Global API Standardization (to_ prefix)
Objective: Standardize all conversion and constructor functions to use the `to_` prefix.

- [x] `dataframe` → `to_dataframe`
- [x] `factor` → `to_factor`
- [x] `to_date` → `to_date`
- [x] `to_datetime` → `to_datetime`
- [x] `str_string` → `to_string`
- [x] `to_symbol` → `to_symbol`
- [x] `expr` → `to_expr`
- [x] `exprs` → `to_exprs`
- [x] Implement `to_bool` in `converters.ml`
- [x] **Verify Dead Code Removal**: Compile the project (`dune build`) to ensure no missing references were accidentally created. 

---

## Phase 4: Code Unification & Deduplication

Identify and merge overlapping functionality to simplify maintenance and reduce complexity across the codebase.

- [x] **Identify Duplicate Logic**: Identified and merged converter logic in `converters.ml`.
- [x] **Extract Helper Functions**: Extracted `lift_unary_converter` to handle Vector/List lifting.
- [x] **Unify Disparate Implementations**: Unified error handling across all core converters.
- [x] **Consolidate Constants**: (Ongoing as part of general cleanup).
- [x] **Verify Abstractions**: Verified via `dune test`.

---

## Phase 5: Final Verification & Commit

Ensure the refactored codebase remains functionally identical to the baseline from Phase 1.

- [x] **Run Unit & Golden Tests**: Execute `dune test` and confirm 100% pass rate.
- [x] **Run Integration Tests**: Verified via `t_demos` adaptation and build verification.
- [x] **Check Compiler Warnings**: Ensure `dune build` runs cleanly without new warnings about unused variables or missing patterns.
- [x] **Commit Changes**: Push the final state to the `more-julia-refactor` branch.
