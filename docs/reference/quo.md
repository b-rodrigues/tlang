# quo

Capture an expression with its lexical environment (quosure)

Captures the provided expression as a **Quosure**: a pair of the expression AST and the current lexical environment. When later evaluated with `eval()`, the expression is evaluated in the captured environment, not the caller's. This matches the semantics of `rlang::quo()` in R.

## Parameters

- **x** (`Any`): The expression to capture as a quosure.


## Returns

The captured expression with its environment.

## Examples

```t
x = 10
q = quo(1 + x)   -- captures x = 10
x = 99
eval(q)           -- returns 11, not 100
```

