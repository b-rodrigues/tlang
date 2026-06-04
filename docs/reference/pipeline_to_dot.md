# pipeline_to_dot

Export Pipeline/MetaPipeline as DOT Graph

Returns a string containing a Graphviz DOT representation of the pipeline or metapipeline dependency graph, including node names, language runtimes, and execution statuses.

## Parameters

- **p** (`Pipeline|MetaPipeline`): The pipeline or metapipeline.


## Returns

A DOT graph string.

## Examples

```t
pipeline_to_dot(p)
```

## See Also

[pipeline_dot](pipeline_dot.html), [pipeline_to_mermaid](pipeline_to_mermaid.html)

