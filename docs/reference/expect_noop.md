# expect_noop

Node noop assertion

Passes if `node_name` noop flag matches the expected value.

## Parameters

- **p** (`Pipeline`): The pipeline.

- **node_name** (`String`): The node name.

- **expected** (`Bool`): Expected noop value.


## Returns

`Expect_pass` if matches; `Expect_stop` otherwise.

## Examples

```t
assert(expect_noop(p, "heavy_job", true))
```

