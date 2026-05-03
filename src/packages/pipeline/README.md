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
| `read_node(p, name)` | Read a node value plus diagnostics from an in-memory pipeline |
| `read_node(name)` | Read a node artifact from the pipeline registry |
| `read_pipeline(p)` | Read aggregated diagnostics and node metadata from a pipeline |
| `which_nodes(p, predicate)` | Filter `read_pipeline(p).nodes` records with concise predicates |
| `errored_nodes(p)` | Return only node records with captured errors |
| `filter_node(p, pred)` | Filter nodes by predicate |
| `select_node(p, ...)` | Select nodes by name |
| `mutate_node(p, ...)` | Add/modify nodes |
| `rename_node(p, ...)` | Rename nodes |
| `arrange_node(p, ...)` | Reorder node definitions |
| `trace_nodes(p, names)` | Extract node sub-graph |

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
