# ifelse

Vectorized If-Else

Evaluates a condition and returns values from `true_val` or `false_val` depending on the condition. Supports missing value handling via the `missing` argument.

## Parameters

- **condition** (`Vector[Bool]`): The logical condition to evaluate.
- **true_val** (`Any`): Expected return value when condition is true.
- **false_val** (`Any`): Expected return value when condition is false.
- **missing** (`Any`): (Optional) Value to return when condition is NA.
- **out_type** (`String`): (Optional) Explicit output type casting.

## Returns

A vector of the resulting values.

## Examples

```t
ifelse([true, false, NA], "Yes", "No", missing: "Unknown")
```

