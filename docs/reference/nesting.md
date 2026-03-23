# nesting

Helper to find combinations present in data

nesting() is used inside expand() or complete() to only use combinations that already appear in the data.

## Parameters

- **...** (`Symbol`): The columns to nest (use $col syntax).


## Returns

A special marker for expand/complete.

## Examples

```t
expand(df, nesting($year, $month))
```

