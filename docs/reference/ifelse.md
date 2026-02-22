# ifelse

Vectorized if-else

Vectorized conditional selection. Returns values from `true_val` or `false_val` depending on whether `condition` is true or false.

## Parameters

- **condition** (`Bool`): | Vector[Bool] The condition to check.
- **true_val** (`Any`): | Vector[Any] Value to return if condition is true.
- **false_val** (`Any`): | Vector[Any] Value to return if condition is false.
- **missing** (`Any`): (Optional) Value to return if condition is NA. Defaults to NA.
- **out_type** (`String`): (Optional) Force-cast output values to Int, Float, String, or Bool.

## Returns

| Vector[Any] A scalar when `condition` is scalar, otherwise a vector aligned to `condition`.

## Examples

```t
ifelse(x > 5, "High", "Low")
ifelse(x % 2 == 0, x, 0)
```

