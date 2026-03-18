# quos

Capture multiple expressions with their lexical environment (quosures)

Captures one or more expressions as a List of Quosure values, each paired with the current lexical environment. Supports named arguments. Matches the semantics of `rlang::quos()` in R.

## Parameters

- **...** (`Any`): One or more expressions to capture as quosures.


## Returns

A list of captured quosures.

## Examples

```t
x = 10
qs = quos(a = 1 + x, b = 2 * x)
eval(qs$a)   -- returns 11
```

