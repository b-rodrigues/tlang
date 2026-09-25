# pipeline_status

Pipeline health table

Joins pipeline structure with the latest build log into a single per-node health table. Failed nodes sort first so the root cause is visible without extra calls.  Columns: - `name` — node name (String) - `runtime` — e.g. "T", "R", "Python" (String) - `status` — build status from the latest matching log ("Completed", "Errored", "SoftFailed", "Cached", "Skipped", ...), or NA when the pipeline has no matching build log yet - `duration` — node build duration in seconds (Float), or NA - `path` — Nix store path of the node output, or NA - `error` — `code: message` for failed nodes (truncated), or NA

## Parameters

- **pipeline** (`Pipeline`): The pipeline to summarize.


## Returns

One row per node, failed nodes first.

## Examples

```t
pipeline_status(p)
pipeline_status(p) |> filter($status == "Errored")
```

## See Also

[build_log_to_frame](build_log_to_frame.html), [build_log](build_log.html), [pipeline_to_frame](pipeline_to_frame.html)

