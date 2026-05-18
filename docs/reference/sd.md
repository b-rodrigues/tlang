# sd

Standard Deviation

Calculates the sample standard deviation of a numeric vector. With `weights`, uses the weighted population denominator (`sum(weights)`).

## Parameters

- **x** (`Vector`): | List The numeric data.

- **na_rm** (`Bool`): (Optional) logical. Should missing values be removed? Default is false.

- **weights** (`Vector[Float]`): | List[Float] = NA Optional non-negative observation weights.


## Returns

The standard deviation.

## Examples

```t
sd([1, 2, 3, 4, 5])
-- Returns = 1.5811...
```

## See Also

[var](var.html), [mean](mean.html)

