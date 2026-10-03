# str_pad

Pad strings to a target width

Pads strings on the left, right, or both sides until they reach a requested width. Width is measured in characters (Unicode code points), so multi-byte UTF-8 strings are padded correctly and never split.

## Parameters

- **x** (`String | List | Vector`): The input string(s).

- **width** (`Int`): The target character width (non-negative).

- **side** (`String`): [Optional] One of "left", "right", or "both". Defaults to "left".

- **pad** (`String`): [Optional] The padding text. Defaults to " ".


## Returns

The padded string.

## Examples

```t
str_pad("7", 3, side = "left", pad = "0")
-- Returns = "007"
```

