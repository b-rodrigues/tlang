# sum

Sum of numeric values

Calculates the sum of values in a List or Vector.

## Parameters

- **x** (`List[Number]`): | Vector[Number] The collection to sum.
- **na_rm** (`Bool`): = false Remove NA values before summing.

## Returns

| NA The sum of values.

## Examples

```t
sum([1, 2, 3])
-- Returns: 6

sum([1, NA, 3], na_rm: true)
-- Returns: 4
```

