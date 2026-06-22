# node_fork

Static pipeline multi-way branch

Evaluated at pipeline construction time. Takes condition-value pairs and returns the value for the first truthy condition. If no condition matches, returns a null marker (node excluded). Provide `.default` to control the fallback value. This preserves Nix's static DAG requirement — the condition is checked before the build.  `node_fork` is only meaningful as the direct value of a node binding inside a `pipeline { }` block. Using the result outside that context is unsupported.

## Parameters

- **...** (`Any`): Pairs of condition-value arguments.

- **.default** (`Any`): (Optional) Fallback value if no condition matches.


## Returns

| Null The selected node value or null marker.

## Examples

```t
p = pipeline {
model = node_fork(
env("MODEL_TYPE") == "lm", rn(script = "lm.R"),
env("MODEL_TYPE") == "nn", pyn(script = "nn.py"),
.default = rn(script = "baseline.R")
)
}
```

