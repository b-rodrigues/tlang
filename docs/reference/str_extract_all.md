# str_extract_all

Extract all regex matches

Returns every regular-expression match found in each string.

## Parameters

- **s** (`String | List | Vector`): The input string(s).

- **pattern** (`String`): The regular expression to match.


## Returns

Every match, or an empty list when there is no match.

## Examples

```t
str_extract_all("a1b22", "[0-9]+")
-- Returns = ["1", "22"]
```

