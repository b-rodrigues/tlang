# node_when

Static Conditional Pipeline Node Inclusion

Evaluated at pipeline construction time. Returns `value` if `condition` is truthy, otherwise excludes the node from the DAG entirely (the keyed node will not appear in `pipeline_nodes()` and accessing it produces an `Error`).

`node_when` is only meaningful as the direct value of a node binding inside a `pipeline { }` block. Using the result outside that context (arithmetic, `is_na()`, etc.) is unsupported.

## Parameters

- **condition** (`Bool`): The condition to evaluate. Must be deterministic at pipeline-definition time (e.g., a variable, not an I/O call).

- **value** (`Any`): The node value to include if condition is truthy. Typically a `node()`, `rn()`, `pyn()`, or other pipeline node constructor.

## Returns

The `value` if condition is truthy; a null marker that excludes the node from the pipeline DAG otherwise.

## Examples

```t
include_heavy = false

p = pipeline {
  data = [1, 2, 3, 4, 5]
  quick = sum(data)
  heavy = node_when(include_heavy, node(command = "deep analysis", runtime = T))
}

build_pipeline(p)

-- "heavy" does not appear in the pipeline at all when include_heavy is false
"heavy" in pipeline_nodes(p)  -- false
```

```t
-- With an R node
p = pipeline {
  data = [1, 2, 3, 4, 5]
  total = sum(data)
  r_out = node_when(true, rn(
    command = <{ list(lang = "R", val = 42L) }>,
    serializer = ^json
  ))
}

build_pipeline(p)
read_node(p.r_out)  -- {lang: "R", val: 42}
```

## See Also

[node_fork](node_fork.html), [node](node.html), [rn](rn.html), [pyn](pyn.html), [build_pipeline](build_pipeline.html)
