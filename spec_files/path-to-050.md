# Path to T 0.5.0: Hardening Roadmap

This document outlines the critical hardening tasks required to transition T from its current state to a stable **0.5.0** release. The goal is to move from "feature validation" to "production-grade robustness."

---

## 1. Core Language & Execution Safety

### Context-Aware Error Messages
* [x] **Source Locations**: Ensure every `Error()` return in the interpreter and analyzer carries a `Lexing.position`. Users should never see a naked `TypeError: "expected int"`; they should see `[L12:C5] TypeError: "expected int, got float"`.
* [x] **Pipeline Debugging**: When a pipeline node fails, the error message must include the node name. (Implemented prefixes for interpreter re-runs).

### REPL & CLI Stability
* [x] **Signal Handling**: Hardened Ctrl+C handling. Interrupting a long-running T expression should return to the prompt without leaking OCaml exceptions or corrupting the global state.
* [x] **CLI Argument Parsing**: Audit all CLI entry points (`run`, `init`, `test`) for robust error handling when passed malformed paths or conflicting flags.

---

## 2. Apache Arrow & FFI Hardening

### C FFI Audit
* [ ] **Refcounting**: Perform a manual audit of `src/arrow/arrow_stubs.c` to ensure all `g_object_unref` calls match their allocations. Use Valgrind/ASAN in a dedicated CI job.
* [ ] **Buffer Bounds**: Verify that all direct memory access in the OCaml -> C bridge checks buffer lengths before reading/writing, preventing segfaults on malformed Arrow tables.

### Native Path Validation
* [x] **CI Enforcement**: Add a CI job that fails if the "fallback" (pure OCaml) path is taken when the native Arrow backend is supposed to be active. (Verified in `.github/workflows/arrow-validation.yml`).
* [ ] **Zero-Copy Integrity**: Strictly validate that `select` and `filter` operations on Arrow-backed DataFrames maintain zero-copy views. Add internal telemetry or "debug mode" flags to verify this in tests.

---

## 3. Pipeline Engine Robustness

### DAG Integrity
* [x] **Cycle Detection**: Implement explicit cycle detection in the pipeline builder to provide a clean "Circular Dependency" error instead of a stack overflow.
* [ ] **Serialization Versioning**: Add a version header to serialized pipeline nodes (`.tcache` or similar). Version 0.5.0 should gracefully reject (or migrate) nodes from older versions.

### Polyglot Shell Nodes
* [ ] **Escape Handling**: Harden the command generation for `shn` (shell nodes). Ensure that passing complex strings (with quotes, backticks, or newlines) between T, R, and Python nodes does not lead to shell injection or broken scripts.
* [ ] **Environment Hermeticity**: Ensure that shell nodes derive their environment exclusively from the `tproject.toml` configuration, preventing "it works on my machine" issues.
* [x] **Cross-Runtime Error Propagation**: Enhance `read_node` and `pipeline_run` to capture and surface detailed error messages (including tracebacks) from R, Python, and Shell nodes that fail during Nix builds. Errors should be surfaced as first-class `VError` values, allowing inspection via `explain(p.node_name)`.

### PMML Interchange
* [ ] **Schema Validation**: When exporting or importing models via PMML (e.g., from `lm()`), validate the XML against the PMML 4.4.1 schema to ensure interoperability with other tools (Scikit-Learn, R).

---

## 4. Standard Library & Ecosystem

### Standard Library Consistency
* [ ] **Function Signature Audit**: Ensure consistent parameter naming across all packages (e.g., `na.rm` vs `handle_na`).
* [ ] **Vectorization Coverage**: Verify that all core math functions in `src/packages/math` and `src/packages/stats` are fully vectorized and handle `Vector` vs `Scalar` inputs predictably.

### Quarto Extension
* [ ] **Versioning**: Sync the Quarto extension version in `_extension.yml` with the core T version.
* [ ] **Self-Contained Installer**: Provide a single `quarto install` command that doesn't require manual file copying.
* [ ] **Lua Linter**: Integrate `selene` or `luacheck` into the Quarto CI to catch Lua-specific bugs.

### Package Manager (`t update`)
* [ ] **Remote Tag Matching**: Finalize and verify the logic in `update_manager.ml`. Users should be able to run `t update` and see a clear diff of what will change in their `flake.lock`.
* [ ] **Rollback Safety**: Ensure `t update` creates a backup of `flake.lock` (or relies on git) so users can safely undo a dependency sync.

### LSP Server
* [ ] **Performance**: Optimize the LSP for files >1000 lines. Ensure the type-checking pass isn't blocking the main UI thread in editors.

---

## 5. Documentation & Release Prep

### Documentation Audit
* [ ] **Reconcile Planning Docs**: Delete or archive stale `spec_files/*.md` that refer to unimplemented features as "current."
* [ ] **Performance Transparency**: Update `docs/performance.md` with explicit benchmarks comparing the "Native Path" vs. "Fallback Path" for common operations (filter, mutate, summarize).

### Release Checklist
* [ ] **The "Happy Path" Smoke Test**: A single script that runs in CI: `init` -> `add dep` -> `update` -> `run` -> `test`. If this script fails, the release is blocked.
* [ ] **Version Stamp**: automate the update of version strings across `dune-project`, `flake.nix`, and `_extension.yml`.

---

## 6. Infrastructure & Hermeticity

### Pure Nix Environment
* [ ] **Build Isolation**: Audit the `flake.nix` to ensure no "impure" lookups are happening during the build phase.
* [ ] **Binary Distribution**: Ensure the `nix build` produces a statically linked (where possible) or correctly wrapped binary for Linux and macOS.
