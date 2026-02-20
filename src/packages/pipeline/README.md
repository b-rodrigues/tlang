# pipeline

Pipeline definition and introspection.

## Functions

| Function | Description |
|----------|-------------|
| `pipeline_nodes(p)` | List the node names in a pipeline |
| `pipeline_deps(p)` | Get dependency graph of a pipeline |
| `pipeline_node(p, name)` | Get a specific node's value |
| `pipeline_run(p)` | Re-run a pipeline (with incremental caching) |
| `build_pipeline(p)` | Emit `pipeline.nix` and materialize node artifacts |
| `read_node(name)` | Read a node artifact from the pipeline registry |
| `load_node(name)` | Load/read a node artifact by name |

## Examples

```t
p = pipeline {
  data <- read_csv("sales.csv")
  cleaned <- data |> filter($amount > 0)
  summary <- cleaned |> summarize(total = sum($amount))
}

pipeline_nodes(p)       -- ["data", "cleaned", "summary"]
pipeline_deps(p)        -- dependency graph
p.summary               -- access a node directly
pipeline_run(p)         -- re-run with caching
```

## Status

Built-in package — included with T by default.
