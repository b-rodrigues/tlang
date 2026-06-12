# fct_lump_min

Lump factor levels below a minimum count

Collapses factor levels whose counts fall below a minimum threshold.

## Parameters

- **x** (`Vector[Factor]`): A factor vector.

- **min** (`Int`): Minimum count threshold. Levels below this are lumped.

- **other_level** (`String`): = "Other" Name for the collapsed catch-all level.


## Returns

A factor vector with rare levels lumped.

## Examples

```t
fct_lump_min(fct, min = 5)
```

