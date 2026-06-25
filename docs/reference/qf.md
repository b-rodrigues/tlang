# qf

F distribution quantile (inverse CDF)

Returns the quantile (inverse cumulative probability) from the F distribution with given degrees of freedom.

## Parameters

- **p** (`Float`): The probability (0 < p < 1).

- **df1** (`Int`): Degrees of freedom 1.

- **df2** (`Int`): Degrees of freedom 2.


## Returns

The quantile.

## Examples

```t
qf(0.95, 2, 10)
```

