# fct_reorder

Order factor levels by another vector

Reorders factor levels using summary statistics computed from a companion numeric vector.

## Parameters

- **f** (`Vector[Factor]`): A factor vector.

- **x** (`Vector[Number]`): A numeric vector used to compute order.

- **.desc** (`Bool`): = false Sort in descending order.


## Returns

A factor vector with levels reordered by the summary of x.

## Examples

```t
fct_reorder(fct, values)
fct_reorder(fct, values, .desc = true)
```

