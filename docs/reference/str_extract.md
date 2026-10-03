# str_extract

Extract the first regex match

Returns the first regular-expression match found in each string. Returns NA when the pattern does not match.

## Parameters

- **s** (`String | List | Vector`): The input string(s).

- **pattern** (`String`): The regular expression to match.


## Returns

The first match, or NA when there is no match.

## Examples

```t
str_extract("abc123def", "[0-9]+")
-- Returns = "123"
```

