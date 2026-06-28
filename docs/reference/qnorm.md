# qnorm

Normal distribution quantile (inverse CDF)

Returns the quantile (inverse cumulative probability) from the normal distribution with given mean and standard deviation.

## Parameters

- **p** (`Float`): The probability (0 < p < 1).

- **mean** (`Float`): = 0 The mean of the distribution.

- **sd** (`Float`): = 1 The standard deviation of the distribution.


## Returns

The quantile.

## Examples

```t
qnorm(0.975)
qnorm(0.5, mean = 5, sd = 2)
```

