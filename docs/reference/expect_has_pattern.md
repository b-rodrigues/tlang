# expect_has_pattern

Node dynamic branching pattern assertion

Passes if `node_name` is defined with a dynamic branching pattern (e.g. mapping or crossing).

## Parameters

- **p** (`Pipeline`): The pipeline.

- **node_name** (`String`): The node name to inspect.


## Returns

`Expect_pass` if pattern exists; `Expect_stop` otherwise.

## Examples

```t
assert(expect_has_pattern(p, "train_model"))
```

