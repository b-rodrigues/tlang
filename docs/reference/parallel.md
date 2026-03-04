# parallel

Combine Pipelines in Parallel

Combines two pipelines that are intended to run independently. Errors immediately if any node name exists in both pipelines. Outputs are not automatically wired.

## Parameters

- **p1** (`Pipeline`): The first pipeline.
- **p2** (`Pipeline`): The second pipeline.

## Returns:

Returns: A merged pipeline with all nodes from both.

## Examples

```t
parallel(p_r_model, p_py_model)
```

## See Also

[union](union.html), [chain](chain.html)

