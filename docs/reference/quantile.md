# quantile

Quantiles

Computes the quantile of a distribution at a specified probability.

## Parameters

- **x** (`Vector`): | List The numeric data.
- **probs** (`Float`): The probability (0 to 1).
- **na_rm** (`Bool`): (Optional) Should missing values be removed? Default is false.

## Returns

The quantile value.

## Examples

```t
quantile(x, 0.5)
-- Returns median
```

## See Also

[mean](mean.md), [median](median.md)

