# pipeline_to_dot

Export Pipeline/MetaPipeline as DOT Graph

Returns a string containing a Graphviz DOT representation of the pipeline or metapipeline dependency graph, including node names and language runtimes.  For MetaPipelines, sub-pipelines are rendered as DOT subgraph clusters by default, providing visual grouping of related nodes. Set flatten = true to get a flat diagram.

## Parameters

- **p** (`Pipeline|MetaPipeline`): The pipeline or metapipeline.

- **flatten** (`Bool`): = false Flatten meta-pipeline subgraphs into a single level.

- **title** (`Str`): = None Optional graph title. Auto-detected from tproject.toml when omitted.


## Returns

A DOT graph string.

## Examples

```t
pipeline_to_dot(p)
pipeline_to_dot(meta, flatten = true)
pipeline_to_dot(p, title = "My Graph")
```

## See Also

[pipeline_to_mermaid](pipeline_to_mermaid.html)

