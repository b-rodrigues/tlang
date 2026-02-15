# lead

Lead values

Shifts a vector backward by n positions, filling with NA.

## Parameters

- **x** (`Vector`): The input vector.
- **n** (`Int`): (Optional) Number of positions to shift. Default is 1.

## Returns

The shifted vector.

## Examples

```t
lead([1, 2, 3])
-- Returns: [2, 3, NA]
```

## See Also

[lag](lag.md)

