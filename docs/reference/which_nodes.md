# which_nodes

Filter Readable Pipeline Node Records

Returns the node records from `read_pipeline(p).nodes` that satisfy a predicate. Unlike `filter_node`, this is a read-only query helper: it does not return a new Pipeline. Predicates can be written either as explicit functions (for example `\(node) !is_na(node.diagnostics.error)`) or as concise expressions that refer directly to node-record fields such as `name`, `value`, and `diagnostics`.

## Parameters

- **p** (`Pipeline`): The pipeline to inspect.

- **predicate** (`Function`): A predicate over read-pipeline node records.


## Returns

A list of node records from `read_pipeline(p).nodes`.

## Examples

```t
which_nodes(p, !is_na(diagnostics.error))
which_nodes(p, name == "model")
which_nodes(p, \(node) node.name == "model")
```

## See Also

[select_node](select_node.html), [filter_node](filter_node.html), [read_pipeline](read_pipeline.html)

