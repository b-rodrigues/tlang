# enquo

Capture a function argument's expression (non-standard evaluation)

Must be called inside a function body. Captures the unevaluated expression that the caller passed as the named parameter, returning it as an Expr. Accepts exactly one argument: a bare symbol naming one of the function's parameters.

## Parameters

- **param** (`Symbol`): The name of the parameter whose expression to capture.


## Returns

The captured expression object.

## Examples

```t
my_select = \(df = DataFrame, col = Any -> DataFrame) {
col_expr = enquo(col)
eval(expr(df |> select(!!col_expr)))
}
my_select(iris, $Sepal.Length)
```

