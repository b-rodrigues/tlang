# fct_collapse

Collapse multiple levels

Merges several existing factor levels into new grouped levels.

## Parameters

- **x** (`Vector[Factor]`): A factor vector.

- **...**: Named lists mapping new level names to vectors of old level names.


## Returns

A factor vector with collapsed levels.

## Examples

```t
fct_collapse(fct, small = ["a", "b"], large = ["c", "d"])
```

