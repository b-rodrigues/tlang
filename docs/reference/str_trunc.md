# str_trunc

Truncate strings for display

Shortens strings to a maximum character width and appends an ellipsis when needed. Width is measured in characters (Unicode code points), so multi-byte UTF-8 strings are never split mid-character.

## Parameters

- **x** (`String | List | Vector`): The input string(s).

- **width** (`Int`): The maximum character width (non-negative).

- **side** (`String`): [Optional] One of "left", "right", or "center". Defaults to "right".

- **ellipsis** (`String`): [Optional] The ellipsis marker. Defaults to "...".


## Returns

The truncated string.

## Examples

```t
str_trunc("abcdefgh", 5)
-- Returns = "ab..."
```

