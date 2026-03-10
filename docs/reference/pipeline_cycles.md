# pipeline_cycles

Detect Pipeline Cycles

Returns a list of node names involved in dependency cycles. A well-formed pipeline should always return an empty list.

## Parameters

- **p** (`Pipeline`): The pipeline.


## Returns

Names of nodes in cycles (empty if DAG is valid).

## Examples

```t
pipeline_cycles(p)
```

## See Also

[pipeline_assert](pipeline_assert.html), [pipeline_validate](pipeline_validate.html)

