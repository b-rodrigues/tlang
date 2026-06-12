# to_factor

Create factor values

Converts values to factor-encoded vectors with derived or explicit levels.

## Parameters

- **x** (`Vector`): | List | Any The values to convert to factors.

- **levels** (`Vector[String]`): | List[String] (Optional) Explicit level order. Defaults to sorted unique values.

- **ordered** (`Bool`): = false Mark the factor as ordered for ordinal comparisons.


## Returns

A factor vector.

## Examples

```t
to_factor(["a", "b", "a"])
to_factor(["a", "b", "a"], levels = ["b", "a"], ordered = true)
```

