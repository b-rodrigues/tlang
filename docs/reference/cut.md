# cut

Discretize numeric vector

Splits a numeric vector into intervals.

## Parameters

- **x** (`Vector[Number]`): | List[Number] The vector to discretize.
- **breaks** (`Int`): | Vector[Number] Number of bins or specific cut points.

## Returns:

Returns: Vector of interval labels.

## Examples

```t
cut([1, 2, 3, 4, 5], 2)
cut([1, 2, 3, 4, 5], [0, 2.5, 5])
```

