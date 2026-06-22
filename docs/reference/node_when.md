# node_when

Static pipeline node conditional

Evaluated at pipeline construction time. Returns `value` if `condition` is truthy, otherwise returns a null marker that causes the pipeline to exclude the node entirely. This preserves Nix's static DAG requirement — the condition is checked before the build.  `node_when` is only meaningful as the direct value of a node binding inside a `pipeline { }` block. Using the result outside that context (arithmetic, `is_na()`, etc.) is unsupported.

## Parameters

- **condition** (`Bool`): The condition to evaluate.

- **value** (`Node`): The node value to include if condition is true.


## Returns

| Null The node value or null marker.

## Examples

```t
p = pipeline {
model = node_when(env("CI") == "1", pyn(script = "train.py"))
}
```

