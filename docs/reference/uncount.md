# uncount

Expand rows by weight

Repeats each row according to a count column or weight expression.

## Parameters

- **df** (`DataFrame`): The input data frame.

- **weights** (`Column`): The column containing integer weights (bare name or $col reference).

- **.remove** (`Bool`): = true Remove the weights column from the result.


## Returns

A DataFrame with rows expanded according to the weights.

## Examples

```t
uncount(df, $count)
uncount(df, $n, .remove = false)
```

