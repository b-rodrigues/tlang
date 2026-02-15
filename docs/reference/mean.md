# mean

Compute arithmetic mean of numeric values

The mean is the sum of values divided by the count. This function handles NA values explicitly through the na_rm parameter.

## Parameters

- **x** (`Vector[Float]`): | List[Float] Input numeric data. Must contain at least one value.
- **na_rm** (`Bool`): = false Remove NA values before computation.

## Returns

| NA The arithmetic mean, or NA if input contains NA and na_rm is false

## Examples

```t
mean([1, 2, 3])
-- Returns: 2.0

mean([1, NA, 3], na_rm: true)
-- Returns: 2.0

```

## See Also

[sum](sum.md), [sd](sd.md), [median](median.md)

