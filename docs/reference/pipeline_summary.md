# pipeline_summary

Pipeline Summary

Returns a DataFrame with full metadata for every node in the pipeline. This is a convenience wrapper around `pipeline_to_frame`.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

A DataFrame with one row per node and all metadata columns.

## Examples

```t
pipeline_summary(p)
```

## See Also

[select_node](select_node.html), [pipeline_to_frame](pipeline_to_frame.html)

