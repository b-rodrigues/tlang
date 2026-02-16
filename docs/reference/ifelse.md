# ifelse

Vectorized if-else

Vectorized conditional selection. Returns values from `true_val` or `false_val` depending on whether `condition` is true or false.

## Parameters

- **condition** (`Bool`): | Vector[Bool] The condition to check.
- **true_val** (`Any`): | Vector[Any] Value to return if condition is true.
- **false_val** (`Any`): | Vector[Any] Value to return if condition is false.
- **missing** (`Any`): (Optional) Value to return if condition is NA. Defaults to NA.
- **out_type** (`String`): (Optional) Force-cast output to one of: `Int`, `Float`, `String`, `Bool`.

## Returns

A scalar when `condition` is scalar; otherwise a vector aligned to the length of `condition`.

## Examples

```t
ifelse(x > 5, "High", "Low")
ifelse(x % 2 == 0, x, 0)
ifelse(4 > 5, 1, 0)
ifelse([true, false], 1, 0, out_type = "String")
```
