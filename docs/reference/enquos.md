# enquos

Capture variadic argument expressions (non-standard evaluation)

Must be called inside a function body. Captures the unevaluated expressions passed through the variadic `...` parameter as a named List of Expr values. Call with `...` or with no arguments.

## Parameters

- **...** (`Any`): The variadic parameter to capture.


## Returns

A list of captured expressions, preserving argument names.

## Examples

```t
my_summarize = \(df = DataFrame, ... -> DataFrame) {
cols = enquos(...)
eval(expr(df |> summarize(!!!cols)))
}
my_summarize(iris, mean_sep = mean($Sepal.Length))
```

