# Specification: Node Diagnostics — Warnings and Errors as Pipeline Artifacts

Status: Draft
Author: Bruno Rodrigues
Date: 2026-04-11

## Architecture Goal

In a pipeline, warnings and errors are not console noise — they are **data**. They belong to the node that produced them, should be queryable, and must be reproducible. This spec defines how materialized nodes carry their diagnostics, how those diagnostics propagate through the pipeline graph, and how polyglot nodes (Python/R) bridge their native diagnostics into the T-Lang observability system.

Key concept: **Soft-Failure**. A node can "fail" its internal computation but "succeed" at producing a diagnostic artifact (`VError`). This allows a pipeline to complete its build while providing deep, structured error information instead of a generic "build failed" message.

---

Every node output in the Nix store contains diagnostic markers:
- `$out/artifact`: The primary data, or a `VError` JSON object if the node failed.
- `$out/class`: The T-Lang class of the artifact (e.g., `dataframe` or `VError`).
- `$out/warnings`: A JSON list of non-terminal messages captured during execution (optional).

When `read_node()` loads an artifact where `$out/class` is `VError`, it automatically reconstructs a First-Class Error object.

### NodeWarning

```t
type NodeWarning = {
  kind       : WarningKind,     -- NAPropagated | NAExcluded | NAIgnored | ...
  fn         : string,          -- "log", "filter", "rolling_mean", etc.
  na_count   : int,             -- number of NA slots/rows affected
  na_indices : int[],           -- affected positions (capped at first 50; see note on batches)
  message    : string,          -- human-readable summary
  source     : WarningSource    -- Own | Upstream(node_id)
}
```

A captured error is a structured object (serialized as JSON in the build path) containing:

```t
type VError = {
  type    : "VError",
  code    : ErrorCode,          -- RuntimeError | DependencyError | ...
  message : string,             -- The primary error message
  context : dict,               -- Key-value metadata (tracebacks, node_name, etc.)
  location: SourceLoc | null    -- Source file/line if available
}
```

When a node fails, the runner serializes this `VError` to the artifact path and sets the node class to `VError`.

---

## 2. Warning Propagation Through the Pipeline Graph

Warnings **accumulate** across the pipeline, but not by copying — by reference. Each node records its **own** new warnings plus a list of upstream node references that carry warnings. This avoids duplication while preserving full provenance.

```t
let raw     = load("data.csv")
let cleaned = log(raw.col, na_ignore=true)     -- own warning: 5 NAs ignored
let result  = exp(cleaned, na_ignore=true)     -- own warning: 0 NAs; upstream: cleaned

read_node(result).warnings
-- [
--   { kind: NAIgnored, fn: "exp", na_count: 0, source: Own },
--   { kind: NAIgnored, fn: "log", na_count: 5, source: Upstream(cleaned) }
-- ]
```

The `source` field distinguishes between a node's own diagnostics and inherited upstream ones. This allows the pipeline summary to avoid double-counting and to report the true origin of each issue.

---

## 3. Pipeline-End Summary

When a pipeline build completes (via `build_pipeline` or the REPL), T emits a structured summary of nodes that had issues.

### Printed Output

If nodes soft-failed or encountered warnings, the summary provides a breakdown:

```text
✖ Pipeline build captured node errors [5 succeeded, 2 captured errors, 2 had warnings]
  ! Captured error in node: r_err
  ! Captured error in node: py_err
  ? Warnings in node: r_warn
  ? Warnings in node: py_warn
```

- **`!` (Captured error)**: The node computation failed, but produced a `VError` artifact.
- **`?` (Warnings)**: The node computation succeeded, but diagnostic messages were captured.

If any `soft-fail` errors occurred, `build_pipeline` returns an `Error` to the REPL, listing the offending nodes.

### Programmatic Access

```t
read_pipeline(p).diagnostics
-- {
--   warning_nodes: [cleaned, rolling_result, filtered],
--   error_nodes:   [],
--   summary: "3 nodes with warnings, 0 errors"
-- }
```

### Configuring the Summary

The printed summary can be suppressed without losing the data:

```t
pipeline p [warn_on_build = false] {
  ...
}
```

Diagnostics are always recorded regardless of `warn_on_build`. The flag controls only whether the summary is printed at build time.

---

## 4. Querying Diagnostics in Pipeline Logic

Because diagnostics are first-class node attributes, they can be used in pipeline logic. This makes NA handling decisions **explicit in the pipeline graph** rather than hidden in function arguments or implicit in downstream failures.

### Assert a node is clean before reporting

```t
let report_mean = mean(cleaned, na_rm=true)
assert read_node(report_mean).warnings |> length == 0
```

### Branch on upstream NA presence

```t
let safe_col =
  if read_node(cleaned).warnings |> has_kind(NAIgnored)
  then impute(raw.col, method="median")
  else cleaned
```

This pattern is particularly useful when the presence of NAs should trigger a different analytical path rather than just being silently tolerated.

### Inspect NA count before deciding

```t
let na_share = read_node(cleaned).warnings
               |> filter(w => w.kind == NAIgnored)
               |> map(w => w.na_count)
               |> sum
               |> div(row_count(raw))

assert na_share < 0.05   -- fail pipeline if more than 5% of values are NA
```

---

## 5. Diagnostic Suppression

In cases where NAs in a particular column are fully expected and acknowledged, a `suppress_warnings` combinator can silence the printed output for a specific node without removing the diagnostic record:

```t
let cleaned = log(raw.col, na_ignore=true) |> suppress_warnings
```

The node's `.warnings` attribute still contains the full diagnostic metadata. The suppression is itself recorded in the pipeline summary:

```
  ○  log(raw.col)   — warnings suppressed by caller (5 NAs ignored)
```

This ensures that suppression is auditable — it is visible in the pipeline report rather than being an invisible opt-out.

---

## 6. Implementation Notes

### Lazy vs. Eager Evaluation

Warning metadata (specifically `na_count` and `na_indices`) requires the computation to have been run. Diagnostics therefore live on **materialized** nodes only. During pipeline construction (before materialization), `read_node()` on diagnostics is unavailable. Any pipeline logic that branches on diagnostics implicitly creates a materialization boundary at that point.

### Arrow Batch Indices

With Arrow columnar batches, row indices in `na_indices` are **global offsets** into the full column, not batch-local indices. The implementation must maintain a global row counter across batches when populating diagnostic records. The format is:

```t
na_indices: [7, 11, 23]   -- global row offsets, 0-indexed
```

For very large datasets, `na_indices` is capped at the first 50 affected indices. The full count is always recorded in `na_count` regardless of the cap.

### Diagnostic Record Retention

Diagnostic records are retained for the lifetime of the pipeline execution context. They are not persisted to disk unless the user explicitly serializes `read_pipeline(p).diagnostics`. This is consistent with T's reproducibility model: re-running the pipeline with the same inputs will always regenerate the same diagnostic records.

---

## 7. Polyglot Diagnostics Bridge

T-Lang nodes running in Python or R automatically bridge their native diagnostic systems into the pipeline artifacts.

### Python Bridge
- **Errors**: Uncaught exceptions are caught by the node runner, and the traceback is serialized into a `VError` artifact.
- **Warnings**: The runner uses `warnings.catch_warnings(record=True)` to intercept `warnings.warn()` calls, persisting them to the `$out/warnings` artifact.

### R Bridge
- **Errors**: Handled via `tryCatch()`. Errors are converted to `VError` JSON.
- **Warnings**: Handled via `withCallingHandlers()`. Warnings are collected while allowing execution to continue, then persisted to `$out/warnings`.

---

## 8. Introspection with `explain()`

For nodes that are in an error state (class `VError`), T provides an `explain()` builtin to provide human-readable investigation:

```t
hu = read_node("failing_node")
explain(hu)
```

**Output:**
```text
Error(RuntimeError: "[L1:C5] ValueError: Critical error in node logic")
Context:
  runtime_traceback: "Traceback (most recent call last): ..."
  node_name: "failing_node"
  node_status: "errored"
```

The system also automatically injects the `node_name` into the error context during `read_node()`, ensuring that even when an error artifact is passed through multiple nodes, its origin is always identifiable.
