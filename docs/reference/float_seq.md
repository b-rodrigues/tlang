# float_seq

Generate a sequence of evenly-spaced floats

Creates a list of `n` floats from `start` to `end` (inclusive), evenly spaced.

## Parameters

- **start** (`Float|Int`): Starting value.

- **end** (`Float|Int`): Ending value.

- **n** (`Int`): Number of values (default: 100).


## Returns

List of evenly-spaced floats.

## Examples

```t
float_seq(0, 1, 5)
-- Returns = [0.0, 0.25, 0.5, 0.75, 1.0]
float_seq(start = 0, end = 1, n = 5)
```

