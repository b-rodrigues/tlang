# explain

Explain Value

Returns a dictionary describing the structure and content of a value. Node results from `read_node(...)` are wrapped with node metadata and expose the explained payload under `contents`. Computed pipeline nodes (e.g. `p.node`) also expose `foreign_meta` with shape facts from the build-time `meta` sidecar (dimensions for frames and arrays, n_obs/n_features/formula/order/metrics for models), or NA when absent.

## Parameters

- **x** (`Any`): The value to explain.


## Returns

A structured description of the value.

## Examples

```t
explain(mtcars)
explain(1)
```

## See Also

[str](str.html), [type](type.html)

