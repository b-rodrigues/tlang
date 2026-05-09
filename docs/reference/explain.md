# explain

Explain Value

Returns a dictionary describing the structure and content of a value. Node results from `read_node(...)` are wrapped with node metadata and expose the explained payload under `contents`.

## Parameters

- **x** (`Any`): The value to explain.


## Returns

A structured description of the value.

## Examples

```t
explain(mtcars)
explain(1)
```

## See Also

[str](str.html), [type](type.html)

