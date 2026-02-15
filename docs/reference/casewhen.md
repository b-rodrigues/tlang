# casewhen

Vectorized case-when

Evaluates a series of `condition ~ value` formulas sequentially. Returns the value corresponding to the first true condition for each element.

## Parameters

- **...** (`Formula`): One or more formulas of the form `condition ~ value`.
- **.default** (`Any`): (Optional) Value to return if no condition matches. Defaults to NA.

## Returns

A vector of the matched values.

## Examples

```t
casewhen(
x > 0 ~ "Positive",
x < 0 ~ "Negative",
.default = "Zero"
)
```

