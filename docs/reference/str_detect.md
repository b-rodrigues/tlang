# str_detect

Test whether a regex matches

Returns true when a regular expression matches a string.

## Parameters

- **s** (`String | List | Vector`): The input string(s).

- **pattern** (`String`): The regular expression to test.


## Returns

True when the pattern matches.

## Examples

```t
str_detect("abc", "^[a-z]+$")
-- Returns = true
```

