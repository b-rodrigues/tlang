# expect_computed

Computed node assertion

Passes if the node is computed and has a finished value.

## Parameters

- **node** (`ComputedNode`): | NodeResult The node to check.


## Returns

`Expect_pass` if computed; `Expect_stop` otherwise.

## Examples

```t
assert(expect_computed(res.heavy_job))
```

