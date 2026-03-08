# str_join

Join strings with a separator

Concatenates items of a List or Vector into a single string, separated by `sep`.

## Parameters

- **items** (`List`): | Vector The items to join.
- **sep** (`String`): [Optional] The separator string. Defaults to "".

## Returns:

Returns: The joined string.

## Examples

```t
str_join(["a", "b", "c"], "-")
-- Returns = "a-b-c"
str_join(["a", "b", "c"])
-- Returns = "abc"
```

## See Also

[str_string](string.html)

