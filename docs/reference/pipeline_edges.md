# pipeline_edges

Pipeline Dependency Edges

Returns a list of dependency pairs, each as a two-element list `[from, to]` representing an edge from a dependency to a dependent node.

## Parameters

- **p** (`Pipeline`): The pipeline.

## Returns:

Returns: A list of [dependency, dependent] pairs.

## Examples

```t
pipeline_edges(p)
```

## See Also

[pipeline_leaves](pipeline_leaves.html), [pipeline_roots](pipeline_roots.html), [pipeline_deps](pipeline_deps.html), [pipeline_nodes](pipeline_nodes.html)

