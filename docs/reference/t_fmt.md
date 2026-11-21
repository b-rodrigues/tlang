# t_fmt

Format T Source File

Formats a `.t` file using the canonical T formatter, preserving comments and `<{ ... }>` raw foreign code blocks. By default returns the formatted source string without modifying the file; pass `write = true` to update the file in place, or `check = true` to return a Bool indicating whether the file is already formatted.

## Parameters

- **path** (`String`): Path to the `.t` file to format.

- **write** (`Bool`): = false When true, write formatted output back to `path`.

- **check** (`Bool`): = false When true, return `true` if already formatted, `false` otherwise.


## Returns

Formatted source string, or Bool when `check = true`.

## Examples

```t
t_fmt("src/pipeline.t")
t_fmt("src/pipeline.t", write = true)
t_fmt("src/pipeline.t", check = true)
```

## See Also

[t_fix](t_fix.html), [t_check](t_check.html)

