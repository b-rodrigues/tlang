# Q&A Walkthrough: v0.54.1 — JSON Diagnostics & Streaming

**Branch:** `v0.54.1` (commit `5f589591`)
**Date:** 2026-07-14
**Reviewer:** [your name here]

This document walks through every feature on the v0.54.1 branch, what it does, why it
exists, and how to verify it. Read top-to-bottom or jump to the feature you're reviewing.

---

## Table of Contents

1. [Quick orientation](#1-quick-orientation)
2. [Feature 6.1 — `target_node` on `suggested_fix`](#2-feature-61)
3. [Feature 6.2 — `expected`/`actual` on diagnostic](#3-feature-62)
4. [Feature 6.3 — Centralized `error_class` enum](#4-feature-63)
5. [Feature 6.4 — `node.file` + `node.span.end`](#5-feature-64)
6. [Feature 6.5 — `Add_node_arg` fix application](#6-feature-65)
7. [Feature 6.6 — Streaming NDJSON for `t run --json`](#7-feature-66)
8. [Review fixes applied to 6.6](#8-review-fixes)
9. [Shared env caching](#9-shared-env-caching)
10. [What was dropped](#10-what-was-dropped)
11. [Test coverage](#11-test-coverage)
12. [Breaking changes](#12-breaking-changes)
13. [How to verify](#13-how-to-verify)

---

## 1. Quick orientation

**What is this branch?**
v0.54.1 implements the "agent-facing verification surface" from `spec_files/path-to-0.54.1.md`
§6 — six features that make T's JSON diagnostics structured enough for agents to act on
programmatically, plus streaming output for long-running builds.

**What is T?**
A Nix-mandatory, reproducibility-first functional language for tabular data analysis. Pipelines
are `.t` files parsed by an OCaml interpreter, built by Nix, and executed per-node.

**Key files to know:**

| File | What it does |
|---|---|
| `src/diagnostics.ml` | Core diagnostic type, JSON serialization, `error_class` enum |
| `src/fix.ml` | Fix application engine (Cast, Rename_column, Add_node_arg) |
| `src/pipeline/ndjson_stream.ml` | NDJSON event types and emitters |
| `src/pipeline/builder_internal.ml` | Nix build orchestrator, NDJSON emission, log capture |
| `src/pipeline/builder_utils.ml` | Shared command execution helpers |
| `src/ast.ml` | AST + global `ndjson_mode` flag |
| `src/repl.ml` | CLI entry point (`t run`, `t check`, `t fix`) |
| `tests/test_ndjson.ml` | NDJSON event serialization tests |
| `tests/test_fix.ml` | Fix application tests |

**Commit history on this branch (newest first):**

```
5f589591 Merge branch 't-run-json' into v0.54.1
5df02666 Merge branch 'chore/shared-env-cache' into v0.54.1
1c662067 fix(repl): support --json flag when running expressions
dc5acde4 perf(tests): cache shared Packages.init_env() across test runs
b09aacfc fix(pipeline): address review feedback on feature 6.6 NDJSON streaming
814395fd feat(pipeline): implement streaming NDJSON for t run --json (6.6)
cee5a5bf Merge pull request #472 from b-rodrigues/feature-6-5
dbfbc535 fix(fix): repair apply_add_node_arg correctness bugs
91b216cb feat(fix): implement Add_node_arg fix application and generation
4a8d77f3 Merge pull request #471 from b-rodrigues/feature-6-4
0138fef5 fix(diagnostics): always emit node object even when node_id is None
33b1bacf Merge pull request #469 from b-rodrigues/feature-6-3
8e8bbbee feat(diagnostics): move file/span into node, add span.end (breaking change)
03e808eb feat(diagnostics): centralize error_class as OCaml variant type
80d9106a Merge pull request #468 from b-rodrigues/feature-6-2
e50b4acb feat(diagnostics): add expected/actual fields to diagnostic type
fdc0bca7 Merge pull request #467 from b-rodrigues/feature-6-1
9b16273d feat(diagnostics): add target_node field to suggested_fix
```

---

## 2. Feature 6.1 — `target_node` on `suggested_fix`

**Commit:** `9b16273d`
**Spec:** §6.1

### What changed

The `suggested_fix` type in `src/diagnostics.ml` now has an optional `target_node: string option`
field on `Cast`, `Rename_column`, and `Add_node_arg` variants. This field tells the agent which
node the fix targets, so it doesn't have to infer it from context.

### Why it matters

Without this field, when a diagnostic says "column X has wrong type", the agent has to look at
`caused_by` and figure out which node to apply the fix to. With `target_node`, the fix object
is self-contained: apply this cast to node Y.

### What to check

- `src/diagnostics.ml`: `suggested_fix` type has `target_node` on three variants; JSON
  serialization includes it when present, omits when `None`.
- `src/schema_check.ml`: `Cast` constructor passes `node_name` as `target_node`.
- `src/fix.ml`, `src/packages/pipeline/t_fix.ml`: Pattern matches updated with `_` wildcards
  for the new field.
- `tests/test_fix.ml`: `test_roundtrip` includes `target_node` in fix values and verifies
  JSON roundtrip.

### Example JSON

```json
{
  "kind": "cast",
  "target_node": "clean_loans",
  "column": "loan_amount",
  "cast_to": "double"
}
```

---

## 3. Feature 6.2 — `expected`/`actual` on diagnostic

**Commit:** `e50b4acb`
**Spec:** §6.2

### What changed

The `diagnostic` type now has `diag_expected: string option` and `diag_actual: string option`
fields. These are serialized as structured objects (`{"kind": "arrow_type", "value": "double"}`)
in JSON, not just embedded in the human-readable message string.

### Why it matters

Agents previously had to parse the English message to extract "expected double, got string".
Now they can branch on `expected.value` and `actual.value` programmatically.

### What to check

- `src/diagnostics.ml`: `diagnostic` type has new fields; `diagnostic_to_yojson` serializes
  them as structured objects.
- `src/schema_check.ml`: Type-contract violations pass `Some` values for both fields.
- All other diagnostic constructors pass `None`.
- `tests/test_check.ml`: Test verifying expected/actual appear in JSON output.

### Example JSON

```json
{
  "expected": { "kind": "arrow_type", "value": "double" },
  "actual": { "kind": "arrow_type", "value": "string" }
}
```

---

## 4. Feature 6.3 — Centralized `error_class` enum

**Commit:** `03e808eb` (original), extended in `b09aacfc`
**Spec:** §6.3

### What changed

The ~22 ad-hoc `error_class` string literals scattered across `schema_check.ml`,
`env_check.ml`, `eval.ml`, and `diagnostics.ml` are replaced with a proper OCaml variant type:

```ocaml
type error_class =
  | Structural_error | Name_error | Arity_error | Type_error
  | Value_error | Key_error | Schema_mismatch | Contract_violation
  | Contract_unverifiable | Invalid_expect_placement | Na_warning
  | Missing_tproject | Missing_package | Missing_from_lockfile
  | Nix_generation_error | Nix_eval_error | File_error | Parse_error
  | Stack_overflow | Timeout | Unsupported | Not_implemented
  | Internal_error | assertion_failure | ...
  | Nix_error  (* added in review fixes *)
  | Unknown_error of string  (* catch-all *)
```

With `error_class_to_string` and `error_class_of_string` for JSON serialization.

### Why it matters

The spec requires a "stable enum documented alongside the OCaml error variants" so there's a
1:1 mapping maintainers can keep honest. Bare strings are error-prone and don't survive refactors.

### What to check

- `src/diagnostics.ml`: Type definition, serialization/deserialization functions.
- `src/schema_check.ml`, `src/env_check.ml`, `src/eval.ml`: All use variant constructors
  instead of string literals.
- `tests/test_ndjson.ml`: Roundtrip tests for all enum values.
- `tests/test_check.ml`: `check_eq "of_verror: error_class maps to structural_error"` compares
  against the new type.

---

## 5. Feature 6.4 — `node.file` + `node.span.end`

**Commits:** `8e8bbbee` + `0138fef5`
**Spec:** §6.4

### What changed

The diagnostic JSON shape changed:

**Before:**
```json
{
  "file": "pipeline.t",
  "node": { "id": "clean_loans", "lang": "r" },
  "span": { "start": [14, 3] }
}
```

**After:**
```json
{
  "node": {
    "id": "clean_loans",
    "lang": "r",
    "file": "pipeline.t",
    "span": { "start": [14, 3], "end": [14, 27] }
  }
}
```

`file` moved into `node`; `span` gained `end`. The `node` object is always present (even when
`node_id` is `None`, it emits `"node": null`).

### Why it matters

The spec defines this shape. Agents parsing diagnostics need file and span info to locate the
problem in the source. Having `file` outside `node` meant agents had to handle two different
locations for the same information.

### What to check

- `src/diagnostics.ml`: `diagnostic_to_yojson` restructured; `diag_end_line`/`diag_end_column`
  fields added.
- `tests/test_check.ml`: Tests verifying the new JSON structure.
- `0138fef5` is a follow-up fix ensuring `node` is always present (even with `node_id = None`).

### **Breaking change**

Agent tooling that reads `file` at the top level will break. The `file` field is now inside
`node`. Document this in changelog.

---

## 6. Feature 6.5 — `Add_node_arg` fix application

**Commits:** `91b216cb` + `dbfbc535`
**Spec:** §6.5

### What changed

`apply_fix` in `src/fix.ml` now returns `true` for `Add_node_arg` fixes (previously returned
`false`). The implementation:

1. Reads the pipeline file
2. Finds the node definition matching `target_node`
3. Inserts the argument (e.g., `na_rm = true`) into the node's argument list
4. Adds a comma after the previous argument if needed
5. Matches sibling indentation

Returns `bool` to distinguish: fix applied (`true`) vs. target not found (`false`).

### Why it matters

When `t check --schema` detects a node that's missing a required argument (like `na_rm` on a
function that has NA values), it emits an `Add_node_arg` suggested fix. Previously this fix
was a no-op. Now `t fix` can apply it mechanically.

### What to check

- `src/fix.ml`: `apply_add_node_arg` implementation; returns `bool`.
- `tests/test_fix.ml`: Tests for basic insertion, comma handling, indentation, target not
  found, and dry-run counting.

### Dropped: `Pin_package_version`

The spec originally included `Pin_package_version` (parse `tproject.toml`, update version
constraint). User decided against it — TOML manipulation adds complexity for a low-value
fix. The stub remains as `apply_pin_package_version` returning `false`.

---

## 7. Feature 6.6 — Streaming NDJSON for `t run --json`

**Commits:** `814395fd` + `b09aacfc` + `1c662067`
**Spec:** §6.6

This is the largest feature on the branch. It makes `t run` emit structured JSON events as
the pipeline executes, so agents can react to the first failing node without waiting for the
whole DAG.

### Architecture

```
t run --json pipeline.t
        │
        ▼
  ┌─────────────┐     stdout (NDJSON)     ┌──────────────┐
  │  cmd_run    │ ──────────────────────▶  │  Agent/CLI   │
  │  (repl.ml)  │     stderr (build log)   │  parses JSON │
  └──────┬──────┘ ──────────────────────▶  └──────────────┘
         │                                      ▲
         ▼                                      │
  ┌──────────────────┐   on_stdout callback     │
  │ build_pipeline_  │ ────────────────────────┘
  │ internal         │
  │ (builder_        │   per-node stderr → _pipeline/logs/<node>.log
  │  internal.ml)    │
  └──────────────────┘
```

### Key files

| File | Role |
|---|---|
| `src/pipeline/ndjson_stream.ml` | Event types (`run_started`, `node_failed`, `node_skipped`, `run_finished`), seq counter, emit functions, `truncate_tail`, log path helpers |
| `src/ast.ml` | `ndjson_mode` global ref flag |
| `src/pipeline/builder_utils.ml` | `run_command_stream_argv_separate` (split stdout/stderr), `classify_and_update`, shared string helpers |
| `src/pipeline/builder_internal.ml` | NDJSON emission in `build_pipeline_internal`, log capture, output suppression |
| `src/repl.ml` | `--json` flag for `t run` and `t run --expr`, help text |

### Event schema

Every event is a single JSON line with this envelope:

```json
{
  "seq": 1,
  "ts": "2026-07-14T12:34:56.789Z",
  "event": "node_failed",
  "schema_version": "1.0"
}
```

**Event types:**

| Event | When | Extra fields |
|---|---|---|
| `run_started` | First event, once | — |
| `node_failed` | Per failed node | `node: {id, lang}`, `exit_code`, `error_class`, `message`, `log_tail` (last ~200 lines) |
| `node_skipped` | Per skipped node | `node: {id, lang}`, `reason` |
| `run_finished` | Last event, once | `total`, `succeeded`, `failed`, `skipped`, `cached`, `root_causes` |

### What to check

**ndjson_stream.ml:**
- `reset()` resets seq counter
- `truncate_tail` truncates log output to 200 lines
- Timestamps have real millisecond precision
- Log paths: `_pipeline/logs/<node>.log`
- All four emit functions produce valid JSON to stdout

**builder_internal.ml:**
- `classify_and_update` shared parser: detects node building/completion/errors from nix-build stdout
- `is_failed` helper: single definition near top, replaces 4 inline copies
- `succeeded = completed_count + cached_count` (cached nodes count as succeeded)
- Log capture: stderr appended per-node to `_pipeline/logs/<node>.log`
- Output suppression: human-readable output suppressed in JSON mode

**builder_utils.ml:**
- `run_command_stream_argv_separate`: separate stdout/stderr callbacks
- `contains_substring`, `contains_substring_idx`, `extract_nix_drv_path`: shared helpers
- `nix_line_event` type for structured parsing

**repl.ml:**
- `--json` flag on `t run` and `t run --expr`
- Sets `Ast.ndjson_mode` during evaluation
- Suppresses Pretty_print output
- Uses `begin/end` blocks for clarity

### `--expr` support

`t run --expr 'x = 1 + 2; print(x)' --json` also streams NDJSON. The `--json` flag was added
to `cmd_run` in commit `1c662067`.

---

## 8. Review fixes applied to 6.6

Commit `b09aacfc` addresses five review items:

1. **Shared `is_failed` helper** — single definition, no duplication
2. **Real millisecond timestamps** — `Float.rem t 1.0 *. 1000.0` instead of hardcoded `0`
3. **`error_class` unification** — `Nix_error` variant added; `classify_nix_error` does
   structured pattern matching (Type_error for "error:", File_error for "No such file", etc.)
4. **Shared nix-build line parser** — `classify_and_update` handles classification + hashtable
   mutations; human callback and JSON `on_stdout` are thin dispatchers
5. **`shared_env` reverted from t-run-json** — moved to separate branch `chore/shared-env-cache`

---

## 9. Shared env caching

**Commit:** `dc5acde4`
**Branch:** `chore/shared-env-cache` (merged into v0.54.1)

`Packages.init_env()` is now computed once at module load time and reused across all pipeline
builds and check commands.

**Why it's safe:**
- `Env.t` is `Map.Make(String).t` — immutable
- `eval_program` takes env by value, returns new map; `_env` is discarded
- `Serialization_registry.init_builtins()` is idempotent (same `Hashtbl.replace` keys)

**What to check:** `tests/test_runner.ml` — `shared_env` is a module-level binding used by
all tests.

---

## 10. What was dropped

| Feature | Reason |
|---|---|
| `Pin_package_version` (§6.5) | User decided TOML manipulation adds complexity for a low-value fix. Stub remains returning `false`. |

---

## 11. Test coverage

**Total tests:** 2718 (all passing)

**New tests for this branch:**

| File | Tests |
|---|---|
| `tests/test_ndjson.ml` | seq counter, truncate_tail, timestamps with ms, log paths, emit functions, error_class roundtrip |
| `tests/test_fix.ml` | `test_apply_add_node_arg` (basic, comma, indentation, not found, dry-run) |
| `tests/test_check.ml` | expected/actual JSON structure, error_class enum comparison |

**How to run:**
```bash
nix develop --command bash -c 'eval "$shellHook" && dune runtest'
```

---

## 12. Breaking changes

1. **Feature 6.4:** `file` field moved from top-level to inside `node`; `span` now includes
   `end`. Agent tooling that parses `t check --json` output will need to update.
2. **Feature 6.3:** `error_class` values may change case/format slightly due to centralized
   serialization. Agent tooling comparing exact strings should use `error_class_of_string`
   instead.

---

## 13. How to verify

### Build
```bash
nix develop --command bash -c 'eval "$shellHook" && dune build'
```

### Tests
```bash
nix develop --command bash -c 'eval "$shellHook" && dune runtest'
```

### Manual verification

**Features 6.1–6.4 (JSON structure):**
```bash
echo 'x = read_csv("data.csv") |> filter($col == 1)' > /tmp/test.t
nix develop --command bash -c 'eval "$shellHook" && t check --json /tmp/test.t'
```
Inspect output for `node.file`, `node.span.end`, `expected`/`actual`, `error_class`.

**Feature 6.5 (Add_node_arg):**
```bash
nix develop --command bash -c 'eval "$shellHook" && t fix --dry-run /tmp/test.t'
```

**Feature 6.6 (NDJSON streaming):**
```bash
nix develop --command bash -c 'eval "$shellHook" && t run --json pipeline.t'
```
Should see `run_started`, per-node events, `run_finished` — one JSON object per line.

**Shared env:**
```bash
nix develop --command bash -c 'eval "$shellHook" && time dune runtest'
```
Compare wall time with/without `dc5acde4`.

---

*End of walkthrough.*
