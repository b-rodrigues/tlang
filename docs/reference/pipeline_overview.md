# pipeline_overview

Unified pipeline overview table

One call joins pipeline structure with the latest build log into a single per-node table. It replaces three separate calls (`pipeline_to_frame`, `pipeline_status`, `pipeline_config_to_frame`) when you need both static config and live build state. Column names match the source frames so filters copy over unchanged. Failed nodes sort first so the root cause is visible without extra calls.  Columns: - `name` — node name (String) - `runtime` — e.g. "T", "R", "Python" (String) - `serializer` — e.g. "default", "^csv" (String) - `deserializer` — e.g. "default", "^csv" (String) - `noop` — whether the node is a no-op (Bool) - `deps` — names of nodes this node depends on (String, comma-separated) - `depth` — topological depth in the DAG (Int); roots are depth 0 - `command_type` — one of "command" or "script" (String) - `status` — build status from the latest matching log, or NA - `duration` — node build duration in seconds (Float), or NA - `path` — Nix store path of the node output, or NA - `error` — `code: message` for failed nodes, or NA

## Parameters

- **pipeline** (`Pipeline`): The pipeline to summarize.


## Returns

One row per node, failed nodes first.

## Examples

```t
pipeline_overview(p)
pipeline_overview(p) |> filter($status == "Errored")
```

## See Also

[pipeline_config_to_frame](pipeline_config_to_frame.html), [pipeline_status](pipeline_status.html), [pipeline_to_frame](pipeline_to_frame.html)

