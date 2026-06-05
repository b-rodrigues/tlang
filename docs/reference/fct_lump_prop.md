# fct_lump_prop

Lump factor levels below a minimum proportion

Collapses factor levels whose frequency falls below a proportion threshold.

## Parameters

- **x** (`Vector[Factor]`): A factor vector.

- **prop** (`Float`): Minimum proportion threshold. Levels below this are lumped.

- **other_level** (`String`): = "Other" Name for the collapsed catch-all level.


## Returns

A factor vector with rare levels lumped.

## Examples

```t
fct_lump_prop(fct, prop = 0.05)
```

