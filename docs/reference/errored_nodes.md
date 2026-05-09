# errored_nodes

Get Errored Pipeline Nodes

Returns the read-pipeline node records whose `diagnostics.error` field is not `NA`. This is a convenience wrapper around `which_nodes`.

## Parameters

- **p** (`Pipeline`): The pipeline to inspect.


## Returns

A list of node records with captured errors.

## Examples

```t
errored_nodes(p)
```

## See Also

[read_pipeline](read_pipeline.html), [which_nodes](which_nodes.html)

