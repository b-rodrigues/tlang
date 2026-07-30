# expect_dependency

Node dependency assertion

Passes if `to_node` directly or transitively depends on `from_node` in the pipeline DAG.

## Parameters

- **p** (`Pipeline`): The pipeline.

- **from_node** (`String`): The upstream node name.

- **to_node** (`String`): The downstream node name.


## Returns

`Expect_pass` if dependency exists; `Expect_stop` otherwise.

## Examples

```t
assert(expect_dependency(p, "load", "model"))
```

