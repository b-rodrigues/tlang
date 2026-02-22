# trace_nodes

Trace Pipeline Nodes

Prints a visual dependency tree of the pipeline nodes.

## Parameters

- **p** (`Pipeline`): The pipeline to inspect.
- **name** (`String`): (Optional) A specific node's name to trace.
- **transitive** (`Bool`): (Optional) If true, mark transitive dependencies with '*'.

## Returns

Returns invisibly. Prints to the console.

## Examples

```t
p = pipeline { x = 1; y = x + 1 }
trace_nodes(p)
```

