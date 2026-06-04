# pipeline_to_mermaid

Export Pipeline/MetaPipeline as Mermaid Graph

Returns a string containing a Mermaid JS flowchart representation of the pipeline or metapipeline dependency graph, including node names, language runtimes, and execution statuses.

## Parameters

- **p** (`Pipeline|MetaPipeline`): The pipeline or metapipeline.


## Returns

A Mermaid flowchart string.

## Examples

```t
pipeline_to_mermaid(p)
```

## See Also

[pipeline_to_dot](pipeline_to_dot.html)

