# pipeline_to_mermaid

Export Pipeline/MetaPipeline as Mermaid Graph

Returns a string containing a Mermaid JS flowchart representation of the pipeline or metapipeline dependency graph, including node names, language runtimes, and execution statuses.

## Parameters

- **p** (`Pipeline|MetaPipeline`): The pipeline or metapipeline.
- **title** (`Str`, optional): Graph title. Auto-detected from the project name in `tproject.toml` if omitted. Renders as Mermaid YAML frontmatter (`tlang-title:` key).
- **flatten** (`Bool`, default `false`): If `true`, renders meta-pipelines as a flat graph instead of grouping sub-pipelines into subgraph blocks.

## Returns

A Mermaid flowchart string.

## Examples

```t
pipeline_to_mermaid(p)
pipeline_to_mermaid(meta, title = "My Graph")
pipeline_to_mermaid(meta, flatten = true)
```

## See Also

[pipeline_to_dot](pipeline_to_dot.html)

