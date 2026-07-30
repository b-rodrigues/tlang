# expect_serializer

Node serializer assertion

Passes if `node_name` serializer matches the expected serializer.

## Parameters

- **p** (`Pipeline`): The pipeline.

- **node_name** (`String`): The node name.

- **expected** (`String`): | Symbol The expected serializer.


## Returns

`Expect_pass` if matches; `Expect_stop` otherwise.

## Examples

```t
assert(expect_serializer(p, "data", ^csv))
```

