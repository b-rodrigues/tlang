# fct_recode

Rename factor levels

Recodes existing factor levels using named replacements.

## Parameters

- **x** (`Vector[Factor]`): A factor vector.

- **...**: Named replacements in the form `new_name = old_name`.


## Returns

A factor vector with renamed levels.

## Examples

```t
fct_recode(fct, high = "H", low = "L")
```

