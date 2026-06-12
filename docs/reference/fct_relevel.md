# fct_relevel

Move selected levels to the front

Explicitly reorders a factor by moving named levels ahead of the remaining levels.

## Parameters

- **x** (`Vector[Factor]`): A factor vector.

- **...**: Level names to move to the front.

- **after** (`Int`): = 0 Position after which to place the moved levels (0 = front).


## Returns

A factor vector with selected levels moved.

## Examples

```t
fct_relevel(fct, "c", "a")
fct_relevel(fct, "high", after = 2)
```

