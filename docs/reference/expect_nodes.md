# expect_nodes

Pipeline nodes assertion

Passes if a pipeline contains exactly the expected node names (including dynamic branch nodes).

## Parameters

- **p** (`Pipeline`): The pipeline to check.

- **expected_names** (`List`): | Vector Expected node names.


## Returns

`Expect_pass` if match; `Expect_stop` otherwise.

## Examples

```t
assert(expect_nodes(p, ["load", "clean", "model"]))
```

