# expect_runtime

Node runtime assertion

Passes if `node_name` runtime matches the expected runtime.

## Parameters

- **p** (`Pipeline`): The pipeline.

- **node_name** (`String`): The node name.

- **expected** (`String`): The expected runtime name (e.g. "R", "Python").


## Returns

`Expect_pass` if matches; `Expect_stop` otherwise.

## Examples

```t
assert(expect_runtime(p, "model", "Python"))
```

