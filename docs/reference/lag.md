# lag

Lag values

Shifts a vector forward by n positions, filling with NA.

## Parameters

- **x** (`Vector`): The input vector.
- **n** (`Int`): (Optional) Number of positions to shift. Default is 1.

## Returns

The shifted vector.

## Examples

```t
lag([1, 2, 3])
-- Returns: [NA, 1, 2]
```

## See Also

[lead](lead.md)

