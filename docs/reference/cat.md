# cat

Print values without escaping

Prints one or more values to stdout using a custom separator. Unlike print(), it does not add a trailing newline and supports custom separators. Strings are printed raw (with escape sequences like \n interpreted).

## Parameters

- **...** (`Any`): Values to print.
- **sep** (`String`): = " " Separator between values.

## Returns



## Examples

```t
cat("Line 1", "Line 2", sep = "\n")
```

