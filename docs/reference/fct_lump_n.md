# fct_lump_n

Keep the most frequent factor levels

Collapses infrequent factor levels into an "Other" bucket while keeping the most frequent levels.

## Parameters

- **x** (`Vector[Factor]`): A factor vector.

- **n** (`Int`): = 10 Number of most frequent levels to keep.

- **other_level** (`String`): = "Other" Name for the collapsed catch-all level.


## Returns

A factor vector with infrequent levels lumped.

## Examples

```t
fct_lump_n(fct, n = 5)
fct_lump_n(fct, n = 3, other_level = "Misc")
```

