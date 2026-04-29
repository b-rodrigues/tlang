# explain

Explain Value

Returns a dictionary describing the structure and content of a value.

When the input is a pipeline node result (for example from `read_node(...)`),
the returned dictionary separates node/container metadata from the explained
payload via a `contents` field.

In the REPL and in `t explain ...`, this dictionary is rendered with a
tree-style CLI view for readability. Programmatically, it is still an ordinary
`Dict`.

## Parameters

- **x** (`Any`): The value to explain.


## Returns

A structured description of the value.

## Examples

```t
explain(mtcars)
explain(1)
node_info = explain(read_node("model"))
node_info.contents
```

## See Also

[str](str.html), [type](type.html)
