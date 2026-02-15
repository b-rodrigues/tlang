# join

Join strings with a separator

Concatenates items of a List or Vector into a single string, separated by `sep`.

## Parameters

- **items** (`List`): | Vector The items to join.
- **sep** (`String`): [Optional] The separator string. Defaults to "".

## Returns

The joined string.

## Examples

```t
join(["a", "b", "c"], "-")
-- Returns: "a-b-c"
join(["a", "b", "c"])
-- Returns: "abc"
```

## See Also

[string](string.md)

