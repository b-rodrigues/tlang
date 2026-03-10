# exprs

Capture multiple expressions

Captures one or more expressions as a List of Expr values. Useful for metaprogramming and non-standard evaluation.

## Parameters

- **...** (`Any`): One or more expressions to capture.


## Returns

A list of captured expressions.

## Examples

```t
exprs(1 + 1, x = 2 * 2)
```

