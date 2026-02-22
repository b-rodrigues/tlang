# args

Get function arguments and their types

Returns a dictionary where keys are parameter names and values are their types. Supports both user-defined lambdas and builtin functions.

## Parameters

- **fn** (`Function`): The function to inspect.

## Returns

A dictionary of name: Type.

## Examples

```t
args(sqrt)
-- Returns: {x: "Number | Vector | NDArray"}

f = \(x: Int, y: Float -> Int) x + y
args(f)
-- Returns: {x: "Int", y: "Float"}
```

