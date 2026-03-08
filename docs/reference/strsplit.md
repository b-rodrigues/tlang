# str_split

Split a string on a delimiter

Splits a string into a list of substrings on each occurrence of `sep`. If `sep` is empty, splits into individual characters. Works transparently on ShellResult values (splits stdout).

## Parameters

- **x** (`String`): | ShellResult The string to split.
- **sep** (`String`): The delimiter to split on.

## Returns:

Returns: A list of substrings.

## Examples

```t
str_split("a,b,c", ",")
-- Returns = ["a", "b", "c"]
files = ?<{ls}>; str_split(files, "\n")
```

## See Also

[str_join](join.html)

