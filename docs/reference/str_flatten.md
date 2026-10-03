# str_flatten

Flatten a collection of strings

Concatenates string collections into a single string with an optional separator.

## Parameters

- **items** (`List | Vector`): The items to flatten.

- **collapse** (`String`): [Optional] The separator. Defaults to "".


## Returns

The flattened string.

## Examples

```t
str_flatten(["a", "b", "c"], collapse = "-")
-- Returns = "a-b-c"
```

