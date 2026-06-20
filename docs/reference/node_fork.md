# node_fork

Static Multi-Way Branch for Pipeline Nodes

Evaluated at pipeline construction time. Takes condition-value pairs and returns the value for the first truthy condition. If no condition matches and `.default` is provided, that value is used; if `.default` is omitted, the node is excluded from the DAG entirely.

`node_fork` is only meaningful as the direct value of a node binding inside a `pipeline { }` block. Using the result outside that context is unsupported.

## Parameters

- **...** (`Any`): Pairs of `condition, value` arguments. Conditions are evaluated in order; the first truthy condition's corresponding value is elected.

- **.default** (`Any`): (Optional) Fallback value if no condition matches. When omitted and no condition matches, the node is excluded from the DAG.

## Returns

The value for the first truthy condition, the `.default` value, or a null marker that excludes the node from the DAG.

## Examples

```t
env_mode = "production"

p = pipeline {
  config = node_fork(
    env_mode == "development", node(command = "dev", runtime = T),
    env_mode == "staging",     node(command = "stg", runtime = T),
    env_mode == "production",  node(command = "prd", runtime = T),
    .default = node(command = "fallback", runtime = T)
  )
}

build_pipeline(p)
read_node(p.config)  -- "prd"
```

```t
-- Fork between R, Python, and T fallback
model_lang = "python"

p = pipeline {
  result = node_fork(
    model_lang == "R",      rn(command = <{ list(lang = "R") }>, serializer = ^json),
    model_lang == "python", pyn(command = <{ {"lang": "py"} }>, serializer = ^json),
    .default = node(command = "t_fallback", runtime = T)
  )
}

build_pipeline(p)
read_node(p.result)  -- {lang: "py"}
```

## See Also

[node_when](node_when.html), [node](node.html), [rn](rn.html), [pyn](pyn.html), [build_pipeline](build_pipeline.html)
