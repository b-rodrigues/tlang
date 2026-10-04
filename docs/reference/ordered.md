# ordered

Create ordered factors

Creates factor vectors marked as ordered for ordinal comparisons.

## Parameters

- **x** (`Any`): The values to convert to an ordered factor. Accepts a vector, a list, or a scalar.

- **levels** (`Vector[String] | List[String]`): (Optional) Explicit level order.


## Returns

An ordered factor vector.

## Examples

```t
ordered(["low", "high", "medium"])
ordered(x, levels = ["low", "medium", "high"])
```

