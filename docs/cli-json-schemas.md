# CLI JSON Schemas

All machine-readable outputs share one shape. Each command envelope has `schema_version`. Version is `"1"` now. `t run --json` uses NDJSON events: only the first `run_started` event carries `schema_version` (`"1.0"`); the `node_completed`, `node_failed`, `node_skipped`, and `run_finished` events do not. Treat both spellings as version 1.

## Shared diagnostic shape

`t check --json` returns:

```
{
  "schema_version": "1",
  "status": "ok" | "error",
  "phase": "parse" | "wire" | "schema" | "env" | "build" | "exec",
  "tier": 1 | 2 | 3,
  "diagnostics": [ Diagnostic ]
}
```

Diagnostic:

```
{
  "id": "T1001",
  "error_class": "type_error" | ...,
  "severity": "error" | "warning",
  "phase": "wire" | ...,
  "node": { "id": string|null, "lang": string|null, "file": string|null,
             "span": { "start": [line, col], "end": [line, col]|null }|null },
  "message": string,
  "expected": { "kind": "arrow_type", "value": string }|null,
  "actual": { "kind": "arrow_type", "value": string }|null,
  "caused_by": [string],
  "suggested_fix": Fix|null
}
```

Fix kinds: `rename_column`, `add_node_arg`, `rename_node`, `replace_text`, `suggest_identifier`, `run_command`. Each fix has `confidence`: `high`, `medium`, `low`. `t fix` applies `rename_column`, `add_node_arg`, `rename_node`, `replace_text`. It never applies `suggest_identifier` or `run_command`. Those need manual work.

## Command envelopes

* `t check --json`: check envelope above. Exit 0 = no diagnostics. Exit 1 = wire/parse. Exit 2 = schema. Exit 3 = env.
* `t fix --json`: `{ schema_version: "1", file, dry_run, applied, skipped, would_apply, skip_notes, entries, diagnostics }`. Entries have `message`, `file`, `outcome` (`would_apply`|`skipped`), `note`. `entries` is populated only when `--dry-run` is active; a real run always reports `[]`. Exit 0 = nothing skipped. Exit 1 = some fix skipped.
* `t diff --json`: `{ schema_version: "1", status, phase: "diff", build_a, build_b, summary, nodes }`. Nodes have `name`, `status`, `class_a`, `class_b`, `reasons`, `affected`, plus `hash` or `hash_a`/`hash_b`. Exit 0 = done. Exit 1 = no logs or compute error.
* `t test --json`: `{ schema_version: "1", status: "passed"|"failed", total, passed, failed, duration_ms, results }`. Results have `file`, `status`, `duration_ms`, `error`. Exit 0 = all passed. Exit 1 = some failed.
* `t run --json`: NDJSON. First event is `run_started` with `schema_version`. Then `node_completed`, `node_failed`, `node_skipped`. Last event is `run_finished` with `status`. Exit 0 = success. Exit 1 = build or runtime error.

## Rules

* Do not parse human text. Use `--json`.
* Confidence `high` means safe to auto-apply. `medium` means review first. `low` means manual step.
* `dry_run` never writes files. Real run writes files bottom-up.
