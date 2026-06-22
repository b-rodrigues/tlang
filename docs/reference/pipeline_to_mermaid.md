# pipeline_to_mermaid

Export Pipeline/MetaPipeline as Mermaid Graph

Returns a string containing a Mermaid JS flowchart representation of the pipeline or metapipeline dependency graph, including node names, language runtimes, and execution error status (errored nodes are highlighted with a red stroke). You can view the diagram in your browser by passing the result to show_plot().  For MetaPipelines, sub-pipelines are rendered as Mermaid subgraph blocks by default, providing visual grouping of related nodes. Set flatten = true to get a flat diagram.

## Parameters

- **p** (`Pipeline|MetaPipeline`): The pipeline or metapipeline.

- **flatten** (`Bool`): = false Flatten meta-pipeline subgraphs into a single level.

- **title** (`Str`): = None Optional graph title. Auto-detected from tproject.toml when omitted.


## Returns

A Mermaid flowchart string.

## Examples

```t
pipeline_to_mermaid(p)
pipeline_to_mermaid(meta, flatten = true)
pipeline_to_mermaid(p, title = "My Graph")
```

## See Also

[pipeline_to_dot](pipeline_to_dot.html)

