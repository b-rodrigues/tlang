# seq

Generate a sequence of integers

Creates a list of integers from start to end, optionally with a step size.

## Parameters

- **start** (`Int`): (Optional) Starting value. Defaults to 1.

- **end** (`Int`): (Optional) Ending value. Defaults to start if by is provided.

- **by** (`Int`): (Optional) Step size. Defaults to 1 or -1.


## Returns

List of integers.

## Examples

```t
seq(5)
seq(1, 5)
seq(start = 1, end = 10, by = 2)
-- Returns = [1, 3, 5, 7, 9]
```

