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

- [ ] **Establish Test Baseline**: Run the full test suite (`dune test` or equivalent) to ensure all tests are passing before making changes.
- [ ] **Review Demos**: Verify that the pipelines in `t_demos` build successfully, as they act as our end-to-end integration tests.
- [ ] **Generate Analysis**: Use `dune` warnings, `grep`, or OCaml dead code analysis tools to generate a list of unused functions, variables, and modules.

---

## Phase 2: Removing Aliases

Aliases create multiple ways to do the same thing, complicating the API and evaluation logic. The goal is to enforce one canonical name per operation.

- [ ] **Identify Aliases**: Create a list of aliases currently in the language. Examples include old node constructor shorthands (like `jl_node` vs `jln`), duplicated built-ins, or overlapping standard library functions in `src/packages/core/packages.ml`.
- [ ] **Search for Usages**: Use exact pattern matching to find all instances where the aliases are used in:
  - `src/` (Compiler and evaluator code)
  - `tests/` (Test scripts and assertions)
  - `docs/` (Documentation and examples)
  - `t_demos/` (Demo projects)
- [ ] **Replace Usages**: Update all identified usages to use the canonical names.
- [ ] **Remove Alias Definitions**: Delete the code that defines or registers the alias (e.g., in `packages.ml` or `eval.ml`).
- [ ] **Verify Alias Removal**: Re-run the tests to ensure the compiler and evaluator still function correctly with only the canonical names.

---

## Phase 3: Dead Code Elimination

Remove unused types, variables, functions, and modules to keep the codebase lean and maintainable.

- [ ] **Remove Unused Variables & Bindings**: Look for variables that are declared but never used (OCaml usually warns about these).
- [ ] **Remove Unreachable Code**: Delete logic branches, match cases, or helper functions that can no longer be reached (especially after alias removal).
- [ ] **Clean Up Standard Packages**: Review `src/packages/core/packages.ml` and `src/packages/` for built-in functions or modules that are no longer referenced or exported.
- [ ] **Remove Orphaned Documentation**: Delete documentation files or comments for features/functions that have been removed.
- [ ] **Prune Dependencies**: Check `tproject.toml` and `flake.nix` files (both in T-Lang and `t_demos`) for dependencies that are no longer required by the language or demos.
- [ ] **Verify Dead Code Removal**: Compile the project (`dune build`) to ensure no missing references were accidentally created. 

---

## Phase 4: Final Verification & Commit

Ensure the refactored codebase remains functionally identical to the baseline from Phase 1.

- [ ] **Run Unit & Golden Tests**: Execute `dune test` and confirm 100% pass rate.
- [ ] **Run Integration Tests**: Navigate to `t_demos` and rebuild the core pipelines (e.g., `onnx_exchange_t`, `pmml_julia_r_interop_t`) to guarantee interop is intact.
- [ ] **Check Compiler Warnings**: Ensure `dune build` runs cleanly without new warnings about unused variables or missing patterns.
- [ ] **Commit Changes**: Push the final state to the `julia-support-refactor` branch.
