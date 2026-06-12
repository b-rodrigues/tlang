# read_pipeline

Read Pipeline Metadata

Returns a dictionary describing a materialized in-memory pipeline, including per-node diagnostics and the aggregated diagnostics summary. The diagnostics summary counts own warnings only (not upstream-inherited ones), so the count reflects which nodes originally produced warnings.

After `build_pipeline(p)`, diagnostics include upstream warnings inherited from ancestor nodes, available via `warning_msg()` or `inspect_node()`.

## Parameters

- **p** (`Pipeline`): The pipeline to inspect.


## Returns

A dictionary with `nodes` and `diagnostics` keys. The `diagnostics.summary` field gives a high-level count. Use `warning_msg()` on individual nodes for full warning details including upstream provenance.

## See Also

[warning_msg](warning_msg.html), [inspect_node](inspect_node.html), [explain](explain.html), [read_node](read_node.html)

