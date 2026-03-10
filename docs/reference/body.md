# body

Get function body

Returns the implementation body of a function. For T functions, it returns the body as an Expr object. For built-ins, it returns metadata about the OCaml implementation.

## Parameters

- **fn** (`Function`): The function to inspect.


## Returns

| String The function body or implementation info.

## Examples

```t
f = \(x) (x + 1)
body(f)
```

