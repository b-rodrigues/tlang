# expr

Capture an expression

Captures the provided expression as an Expr object without evaluating it. Useful for metaprogramming, quotation, and custom evaluation.

## Parameters

- **x** (`Any`): The expression to capture.

## Returns:

Returns: The captured expression object.

## Examples

```t
e = expr(1 + 2)
eval(e)
```

