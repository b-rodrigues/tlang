# fct_expand

Add explicit factor levels

Adds extra levels to a factor without changing existing assignments.

## Parameters

- **x** (`Vector[Factor]`): A factor vector.

- **...**: New level names to add.


## Returns

A factor vector with additional levels.

## Examples

```t
fct_expand(fct, "new_level")
```

