# source

Get function source code

Returns the source code of a function as a string. For built-in functions, it attempts to read the underlying OCaml source file.

## Parameters

- **fn** (`Function`): The function to inspect.


## Returns

The source code of the function.

## Examples

```t
source(print)
```

