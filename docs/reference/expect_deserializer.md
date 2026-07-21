# expect_deserializer

Node deserializer assertion

Passes if `node_name` deserializer matches the expected deserializer.

## Parameters

- **p** (`Pipeline`): The pipeline.

- **node_name** (`String`): The node name.

- **expected** (`String`): | Symbol The expected deserializer.


## Returns

`Expect_pass` if matches; `Expect_stop` otherwise.

## Examples

```t
assert(expect_deserializer(p, "model", ^onnx))
```

