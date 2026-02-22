# cummean

Cumulative Mean

Calculates the cumulative mean of a vector.

## Parameters

- **x** (`Vector`): The input numeric vector.
- **na_rm** (`Bool`): = false Remove NA values before computation.

## Returns

The cumulative mean.

## Examples

```t
cummean([1, 2, 3])
-- Returns: [1.0, 1.5, 2.0]

cummean([1, NA, 3], na_rm: true)
-- Returns: [1.0, 1.0, 2.0]
```

## See Also

[cumsum](cumsum.md), [mean](mean.md)

