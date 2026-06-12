# pipeline_to_dot

Export Pipeline/MetaPipeline as DOT Graph

Returns a string containing a Graphviz DOT representation of the pipeline or metapipeline dependency graph, including node names, language runtimes, and execution statuses.

## Parameters

- **p** (`Pipeline|MetaPipeline`): The pipeline or metapipeline.
- **title** (`Str`, optional): Graph title. Auto-detected from the project name in `tproject.toml` if omitted. Renders as `label=` in the `digraph` header.

## Returns

A DOT graph string.

## Examples

```t
pipeline_to_dot(p)
pipeline_to_dot(p, title = "My Graph")
```

## See Also

[pipeline_to_mermaid](pipeline_to_mermaid.html)

