# Additional Findings for a First Alpha Release

> Date: 2026-03-08  
> Scope: what still seems worth adding or tightening before calling T's first alpha "basically complete"

## Short answer

T already appears to have most of the **basic language and data-manipulation surface** needed for a first alpha: joins, `distinct`, pivots, window functions, large-dataset test files, Arrow performance tests, package/project scaffolding, and an LSP server are all present somewhere in the current repository.

Because of that, I would **not** add many more new language features before alpha. The remaining work looks more like **validation, consistency, and release hardening** than new syntax.

## Things I would *not* treat as alpha blockers anymore

These show up as missing in some older planning docs, but the current repo already contains them:

- `distinct` (`src/packages/colcraft/distinct.ml`)
- joins (`src/packages/colcraft/joins.ml`)
- pivots (`src/packages/colcraft/pivot_longer.ml`, `src/packages/colcraft/pivot_wider.ml`)
- window edge-case tests (`tests/colcraft/test_window_edge_cases.ml`)
- Arrow performance and large-dataset test files (`tests/arrow/test_arrow_performance.ml`, `tests/integration/test_large_datasets.ml`)
- LSP server (`src/lsp_server.ml`)

That means the best remaining additions for alpha are the ones below.

## What else I would add before finalizing alpha

### 1. Native Arrow validation in CI, not just fallback-path coverage

The Arrow codebase now contains zero-copy views and compute helpers (`src/arrow/arrow_column.ml`, `src/arrow/arrow_compute.ml`), but the integration test still treats several native-only checks as effectively optional when the native backend is unavailable:

- `tests/arrow/test_arrow_integration.ml` prints skipped/pass-through messages for native zero-copy checks when the native path is unavailable
- `docs/performance.md` already makes concrete performance claims for 10k / 100k / 1M-row workloads

**Why this matters for alpha:** the repo now makes performance-oriented claims, so alpha should ideally have at least one CI path that proves the native Arrow backend is actually exercised.

**Suggested addition:**
- a dedicated CI job (or documented release command) that runs the Arrow/native path explicitly
- one benchmark smoke test that fails if the native path silently disappears

### 2. One explicit release smoke-test workflow for the user journey

The top-level README promises a user-facing flow centered around:

- `nix run github:b-rodrigues/tlang`
- `t init ...`
- `t run ...`

The pieces seem to exist, but alpha would benefit from one **single scripted smoke path** that validates the basic user journey end-to-end:

1. bootstrap a project
2. run a simple `.t` script
3. read a CSV
4. execute a tiny pipeline

**Why this matters for alpha:** for a first public alpha, "can a new user install it and complete the happy path?" is more important than adding another language feature.

### 3. Tighten package-update UX before calling the tooling complete

There is already substantial package/project scaffolding in `src/package_manager/`, but `src/package_manager/update_manager.ml` still contains a visibly unfinished area:

- `check_remote_tags()` currently only prints that remote-tag checking is not yet implemented

This is not a huge blocker, but it is one of the few clearly unfinished user-facing tooling seams left in the repo.

**Suggested addition:**
- either implement basic remote-tag checking
- or remove/de-emphasize the unfinished UX from alpha-facing docs and keep `t update` intentionally simple

### 4. Reconcile stale planning docs before release

Several planning/spec files still describe features as beta work even though the current repo already includes them. Examples include old references to joins, pivots, and other already-implemented functionality in `spec_files/ROADMAP.md` and `spec_files/archive/hardening-alpha.md`.

**Why this matters for alpha:** confusing release scope is a real product problem. If docs say "not implemented" while the code says otherwise, users and contributors will not know what alpha actually contains.

**Suggested addition:**
- do one documentation audit pass over:
  - `spec_files/ROADMAP.md`
  - `spec_files/archive/hardening-alpha.md`
  - `spec_files/README_PLANNING_DOCS.md`
  - any alpha-facing release notes / summary docs

### 5. Clarify the "fast path vs fallback path" story for DataFrames

`docs/performance.md` already documents an important limitation:

- after `mutate()` / structural changes, tables can materialize to pure OCaml storage and lose the native Arrow handle

That may be acceptable for alpha, but it should be made extremely clear in the release story because it directly affects how "fast" T feels in realistic data workflows.

**Suggested addition:**
- keep alpha scope as-is, but document this limitation prominently
- optionally add a simple `explain()`/debug output or developer note that shows whether a DataFrame is still on the native path

### 6. Publish a very small, honest alpha checklist

At this point, the most valuable addition may simply be a concise "done means done" checklist:

- install works
- REPL works
- `t init` works
- `t run` works
- CSV read/write works
- core dataframe verbs work
- grouped ops and window ops work
- native Arrow path is validated somewhere
- examples run
- docs match the shipped feature set

This would make the alpha feel deliberate rather than open-ended.

## Recommendation

If the goal is a **first alpha**, I would avoid adding brand-new language features now.

Instead, I would finish with this order of priority:

1. **validate the native Arrow path in CI/release testing**
2. **ship one end-to-end user smoke test**
3. **clean up stale planning/docs so the repo tells one coherent story**
4. **either polish or explicitly downscope the unfinished `t update` UX**
5. **publish a short alpha checklist and release note**

That feels like the smallest set of additions that would make the current repository look like a credible, intentional first alpha release.
